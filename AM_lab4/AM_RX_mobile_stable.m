%% SDR AM 接收端 - 固定接收長度 + 分段動態增益（移動場景）
% 說明:
% 1) 總接收時間與 AM_RX.m 相同 (Capture_Time = 5 秒)
% 2) 5 秒內切成短分段，每段更新一次 AGC，以追蹤移動造成的強度變化
% 3) 不是無限連續接收，完成指定時間後即停止並播放結果

clc; clear; close all;

%% 1. 參數設定
SR = 960e3;               % 軟體基頻取樣率
Target_Freq_MHz = 433;    % 接收中心頻率
Capture_Time = 15;         % 總接收長度 (與 AM_RX.m 相同)
frame_time = 0.3;         % 分段長度 (弱訊號移動情境優先)
fs_proc = 192e3;          % DSP 處理頻率
fs_audio_out = 48e3;      % 最終播放取樣率

Ga = -10;                 % 初始 RX Gain
Ga_min = -50;
Ga_max = 0;

% AGC 參數（以防飽和優先）
target_mean = 0.12;       % 目標平均振幅
target_p95 = 0.35;        % 目標 95 百分位振幅
agc_alpha = 0.2;          % 平滑係數 (避免增益跳動)
agc_deadband = 0.02;      % 誤差小於此值不調整
max_up_db = 2.5;          % 每段最多提高增益 (dB)
max_down_db = 6.0;        % 每段最多降低增益 (dB)
clip_guard = 0.70;        % 振幅超過此值視為接近飽和，優先降增益

% 音量平衡
target_audio_rms = 0.2;
audio_gain_smooth = 0.25;

% 容錯
max_retry = 6;

%% 2. 前置計算
decimation_factor = round(SR / fs_proc);
if abs(SR / decimation_factor - fs_proc) > 1
    error('SR 與 fs_proc 比值不接近整數，請調整參數。');
end

frame_len = round(SR * frame_time);
num_frames = ceil(Capture_Time / frame_time);

[b_anti, a_anti] = butter(5, (fs_proc/2) / (SR/2), 'low');
% 音訊濾波: 先高通去低頻擺動，再低通抑制雜訊
[b_audio_hp, a_audio_hp] = butter(3, 80 / (fs_proc/2), 'high');
[b_audio_lp, a_audio_lp] = butter(5, 8e3 / (fs_proc/2), 'low');

% 維持濾波器狀態，避免分段交界產生不連續
zi_anti = zeros(max(length(a_anti), length(b_anti)) - 1, 1);
zi_audio_hp = zeros(max(length(a_audio_hp), length(b_audio_hp)) - 1, 1);
zi_audio_lp = zeros(max(length(a_audio_lp), length(b_audio_lp)) - 1, 1);

% AGC 狀態
mean_abs_ewma = target_mean;
audio_gain = 1.0;

% 拼接音訊緩衝
audio_total = [];
env_last = [];

% 交界淡入淡出，降低分段接縫突波
xfade_len = round(0.01 * fs_audio_out); % 10 ms

%% 3. 初始化硬體
fprintf('=== YTTEK SDR AM 接收端 (固定 %d 秒，分段動態 AGC) ===\n', Capture_Time);
LO_CHANGE(0, Target_Freq_MHz, Target_Freq_MHz);
set_RX_Ref_Level_ELSDR([0 Ga]);

%% 4. 分段接收 + 動態 AGC + 解調
for k = 1:num_frames
    retry_count = 0;
    while true
        try
            rk = RX(1, frame_len);
            break;
        catch ME
            retry_count = retry_count + 1;
            warning('第 %d 段接收失敗 (%d/%d): %s', k, retry_count, max_retry, ME.message);
            if retry_count >= max_retry
                error('硬體連續失敗，停止執行。');
            end
            pause(0.2);
            LO_CHANGE(0, Target_Freq_MHz, Target_Freq_MHz);
            set_RX_Ref_Level_ELSDR([0 Ga]);
        end
    end

    % A) 量測訊號強度並更新 AGC（先防飽和，再慢速補償）
    abs_rk = abs(rk);
    rr_mean = mean(abs_rk);
    rr_p95 = prctile(abs_rk, 95);
    rr_p99 = prctile(abs_rk, 99);

    mean_abs_ewma = (1 - agc_alpha) * mean_abs_ewma + agc_alpha * rr_mean;
    p95_err = target_p95 - rr_p95;
    mean_err = target_mean - mean_abs_ewma;

    if rr_p99 > clip_guard
        % 快速防飽和：高峰過高時先降增益
        step_db = -min(max_down_db, 20 * log10((rr_p99 + 1e-6) / clip_guard));
    elseif abs(p95_err) < agc_deadband && abs(mean_err) < agc_deadband
        step_db = 0;
    elseif p95_err < 0
        % 高振幅偏大：中等速度降增益
        step_db = max(-max_down_db, 20 * log10((target_p95 + 1e-6) / (rr_p95 + 1e-6)));
    else
        % 振幅偏小：慢速升增益，避免追噪聲
        step_db = min(max_up_db, 20 * log10((target_mean + 1e-6) / (mean_abs_ewma + 1e-6)));
    end

    % 注意: 此 SDR 的 Ref Level 越小(越負)通常等效於越高接收增益。
    % 因此 AGC 更新方向要用減號，才能在飽和時把 Ga 往 0 dB 拉回。
    Ga = Ga - step_db;
    Ga = max(Ga_min, min(Ga_max, Ga));
    set_RX_Ref_Level_ELSDR([0 Ga]);

    % B) 前處理 + 降取樣與 envelope 解調
    % 移動時 DC 與 LO 漂移可能變大，先做 IQ 去直流可提升穩定度
    rk_dc = rk - mean(rk);
    rk_col = rk_dc(:);
    [rk_filtered, zi_anti] = filter(b_anti, a_anti, rk_col, zi_anti);
    rx_baseband = downsample(rk_filtered, decimation_factor);

    rx_env = abs(rx_baseband);
    env_last = rx_env;

    % C) 音訊濾波
    rx_audio_raw = rx_env - mean(rx_env);
    [rx_audio_hp, zi_audio_hp] = filter(b_audio_hp, a_audio_hp, rx_audio_raw, zi_audio_hp);
    [rx_audio_filtered, zi_audio_lp] = filter(b_audio_lp, a_audio_lp, rx_audio_hp, zi_audio_lp);

    % D) 重取樣到播放頻率
    audio_frame = resample(rx_audio_filtered, fs_audio_out, fs_proc);

    % E) 每段慢速音量平衡，避免音量忽大忽小
    frame_rms = sqrt(mean(audio_frame.^2) + 1e-12);
    desired_gain = target_audio_rms / frame_rms;
    desired_gain = max(0.25, min(8.0, desired_gain));
    audio_gain = (1 - audio_gain_smooth) * audio_gain + audio_gain_smooth * desired_gain;
    audio_frame = audio_frame * audio_gain;

    % F) 分段拼接時做交界淡入淡出
    if isempty(audio_total)
        audio_total = audio_frame;
    else
        overlap = min([xfade_len, length(audio_total), length(audio_frame)]);
        if overlap > 1
            fade_in = linspace(0, 1, overlap).';
            fade_out = 1 - fade_in;
            audio_total(end-overlap+1:end) = ...
                audio_total(end-overlap+1:end) .* fade_out + audio_frame(1:overlap) .* fade_in;
            audio_total = [audio_total; audio_frame(overlap+1:end)];
        else
            audio_total = [audio_total; audio_frame];
        end
    end

    fprintf('Frame %02d/%02d | mean=%.4f p95=%.4f p99=%.4f | Ga=%.2f dB\n', ...
        k, num_frames, rr_mean, rr_p95, rr_p99, Ga);
end

%% 5. 輸出音訊
if ~isempty(audio_total)
    peak = max(abs(audio_total));
    if peak > 0.98
        audio_total = audio_total * (0.98 / peak);
    end

    % 輸出 WAV 供離線回放與分析
    wav_path = fullfile(pwd, 'AM_RX_mobile_stable_out.wav');
    audiowrite(wav_path, audio_total, fs_audio_out);
    fprintf('已輸出 WAV: %s\n', wav_path);

    fprintf('接收完成，正在播放音訊...\n');
    soundsc(audio_total, fs_audio_out);
else
    warning('未取得有效音訊，略過播放。');
end

%% 6. 畫圖觀察
figure('Name', 'AM 解調波形分析 (固定時長 + 分段 AGC)', 'Color', 'w');
t_plot = (0:length(audio_total)-1) / fs_audio_out;
subplot(2,1,1);
plot(t_plot, audio_total, 'b');
title(sprintf('解調後音訊 (Final Ga = %.2f dB)', Ga));
xlabel('時間 (秒)'); ylabel('振幅');
grid on; axis tight;

subplot(2,1,2);
if ~isempty(env_last)
    t_env = (0:length(env_last)-1) / fs_proc;
    plot(t_env, env_last, 'r');
    title('最後一段 Envelope');
    xlabel('時間 (秒)'); ylabel('振幅');
    grid on; axis tight;
else
    text(0.5, 0.5, 'No Envelope Data', 'HorizontalAlignment', 'center');
    axis off;
end
