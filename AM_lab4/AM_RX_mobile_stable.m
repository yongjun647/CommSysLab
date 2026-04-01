%% SDR AM RX for moving device scenario (continuous + stable AGC)
% This script is based on AM_RX.m but redesigned for continuous reception
% with smoother gain tracking when device distance changes over time.

clc; clear; close all;

%% 1) Parameters
SR = 960e3;                 % SDR baseband sampling rate
Target_Freq_MHz = 433;      % RF center frequency
frame_time = 0.25;          % capture duration per frame (seconds)
fs_proc = 192e3;            % DSP processing rate
fs_audio_out = 48e3;        % audio output rate
rx_len = round(SR * frame_time);

gain_dB = -15;              % initial RX reference level
min_gain_dB = -50;
max_gain_dB = 0;

% AGC control knobs
target_mean = 0.22;         % desired mean(|IQ|)
target_peak = 0.55;         % keep envelope peaks away from clipping
agc_alpha = 0.25;           % EWMA smoothing for measurement
agc_deadband = 0.015;       % no gain update in this error range
max_step_per_frame = 3.0;   % gain update clamp (dB/frame)

% Audio leveling knobs (slow and smooth, prevents loudness pumping)
target_audio_rms = 0.20;
audio_gain_smooth = 0.15;

% Loop and recovery
max_runtime_sec = inf;      % set finite value if needed
max_hw_retry = 8;

%% 2) Precompute filters and helper states
decim = round(SR / fs_proc);
if abs(SR / decim - fs_proc) > 1
    error('SR and fs_proc ratio is not close to integer. Please adjust settings.');
end

[b_anti, a_anti] = butter(5, (fs_proc / 2) / (SR / 2), 'low');
[b_audio, a_audio] = butter(5, 8e3 / (fs_proc / 2), 'low');

% Keep filter states continuous across frames
zi_anti = zeros(max(length(a_anti), length(b_anti)) - 1, 1);
zi_audio = zeros(max(length(a_audio), length(b_audio)) - 1, 1);

% One-pole DC blocker state: y[n] = x[n]-x[n-1] + r*y[n-1]
dc_r = 0.995;
dc_x_prev = 0;
dc_y_prev = 0;

% AGC and audio level states
mean_abs_ewma = target_mean;
peak_ewma = target_peak;
audio_gain = 1.0;

% Crossfade state to reduce frame boundary click
crossfade_ms = 15;
xfade_len = round(crossfade_ms * 1e-3 * fs_audio_out);
last_tail = zeros(xfade_len, 1);

%% 3) Initialize SDR
fprintf('=== YTTEK SDR AM RX (mobile stable mode) ===\n');
try
    LO_CHANGE(0, Target_Freq_MHz, Target_Freq_MHz);
    set_RX_Ref_Level_ELSDR([0 gain_dB]);
catch ME
    error('SDR initialization failed: %s', ME.message);
end

%% 4) Simple monitor plot
fig = figure('Name', 'AM RX Mobile Stable', 'Color', 'w');
tiledlayout(fig, 2, 1);
ax1 = nexttile;
h_env = plot(ax1, nan, nan, 'b');
grid(ax1, 'on');
ylabel(ax1, 'Envelope');
title(ax1, 'Demod Envelope (frame)');

ax2 = nexttile;
h_audio = plot(ax2, nan, nan, 'k');
grid(ax2, 'on');
ylabel(ax2, 'Audio');
xlabel(ax2, 'Time (s)');
title(ax2, 'Output Audio (frame)');

start_t = tic;
hw_fail_count = 0;

fprintf('Running... close the figure window or press Ctrl+C to stop.\n');

%% 5) Continuous receive/demod/play loop
while ishandle(fig)
    if toc(start_t) > max_runtime_sec
        fprintf('Reached max_runtime_sec, stop.\n');
        break;
    end

    try
        % A) Capture
        rk = RX(1, rx_len);
        hw_fail_count = 0;

        % B) Robust AGC measurement (use both mean and peak)
        frame_abs = abs(rk);
        cur_mean = mean(frame_abs);
        cur_peak = prctile(frame_abs, 99.5);

        mean_abs_ewma = (1 - agc_alpha) * mean_abs_ewma + agc_alpha * cur_mean;
        peak_ewma = (1 - agc_alpha) * peak_ewma + agc_alpha * cur_peak;

        err_mean = target_mean - mean_abs_ewma;
        err_peak = target_peak - peak_ewma;

        % Convert error to dB command and apply deadband + clamp
        cmd_mean = 20 * log10((target_mean + 1e-6) / (mean_abs_ewma + 1e-6));
        cmd_peak = 20 * log10((target_peak + 1e-6) / (peak_ewma + 1e-6));
        cmd_db = 0.7 * cmd_mean + 0.3 * cmd_peak;

        if abs(err_mean) < agc_deadband && abs(err_peak) < 2 * agc_deadband
            cmd_db = 0;
        end

        cmd_db = max(-max_step_per_frame, min(max_step_per_frame, cmd_db));
        gain_dB = gain_dB + cmd_db;
        gain_dB = max(min_gain_dB, min(max_gain_dB, gain_dB));

        % Apply gain for next frame
        set_RX_Ref_Level_ELSDR([0 gain_dB]);

        % C) Downsample + envelope detect
        rk_col = rk(:);
        [rk_lp, zi_anti] = filter(b_anti, a_anti, rk_col, zi_anti);
        bb = downsample(rk_lp, decim);
        env = abs(bb);

        % D) DC blocker + audio LPF
        x = env;
        y = zeros(size(x));
        for n = 1:length(x)
            y(n) = x(n) - dc_x_prev + dc_r * dc_y_prev;
            dc_x_prev = x(n);
            dc_y_prev = y(n);
        end

        [audio_proc, zi_audio] = filter(b_audio, a_audio, y, zi_audio);

        % E) Resample to output audio rate
        audio_out = resample(audio_proc, fs_audio_out, fs_proc);

        % F) Smooth audio leveling (frame-to-frame stable loudness)
        frame_rms = sqrt(mean(audio_out .^ 2) + 1e-12);
        desired_gain = target_audio_rms / frame_rms;
        desired_gain = max(0.2, min(8.0, desired_gain));
        audio_gain = (1 - audio_gain_smooth) * audio_gain + audio_gain_smooth * desired_gain;
        audio_out = audio_out * audio_gain;

        % Final safety limiter
        peak_audio = max(abs(audio_out));
        if peak_audio > 0.98
            audio_out = audio_out * (0.98 / peak_audio);
        end

        % G) Crossfade with previous frame to suppress boundary clicks
        if xfade_len > 0 && length(audio_out) > xfade_len
            fade_in = linspace(0, 1, xfade_len).';
            fade_out = 1 - fade_in;
            audio_out(1:xfade_len) = audio_out(1:xfade_len) .* fade_in + last_tail .* fade_out;
            last_tail = audio_out(end - xfade_len + 1:end);
        end

        % H) Play and monitor
        sound(audio_out, fs_audio_out);

        t_env = (0:length(env)-1) / fs_proc;
        t_audio = (0:length(audio_out)-1) / fs_audio_out;
        set(h_env, 'XData', t_env, 'YData', env);
        set(h_audio, 'XData', t_audio, 'YData', audio_out);
        title(ax1, sprintf('Envelope | mean=%.3f peak=%.3f | Ga=%.1f dB', mean_abs_ewma, peak_ewma, gain_dB));
        drawnow limitrate;

        fprintf('Ga=%6.2f dB | mean=%.3f | p99.5=%.3f | audioGain=%.2f\n', ...
            gain_dB, mean_abs_ewma, peak_ewma, audio_gain);

    catch ME
        hw_fail_count = hw_fail_count + 1;
        warning('Loop error (%d/%d): %s', hw_fail_count, max_hw_retry, ME.message);

        % Try to recover SDR setup for transient hardware errors
        try
            LO_CHANGE(0, Target_Freq_MHz, Target_Freq_MHz);
            set_RX_Ref_Level_ELSDR([0 gain_dB]);
        catch
            % Ignore nested error and retry after pause
        end

        if hw_fail_count >= max_hw_retry
            error('Too many consecutive hardware failures, stop execution.');
        end
        pause(0.2);
    end
end

fprintf('AM RX mobile stable loop stopped.\n');
