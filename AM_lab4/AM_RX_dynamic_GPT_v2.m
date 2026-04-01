%% SDR MP3 接收端 - 低雜訊高振幅加強版 (Continuous & Dynamic v2)
% 說明:
% 1) 解調前先做窄頻通道低通，明顯降低寬頻雜訊
% 2) 解調後使用高通+低通形成語音頻帶
% 3) 追加音訊端 AGC 與 soft limiter，提升音量且避免爆音
clc; clear; close all;

%% 1. 參數設定
SR = 960e3;              % 軟體基頻取樣率
Target_Freq_MHz = 433;   % 接收中心頻率
Capture_Time = 0.2;      % 每次擷取秒數
fs_audio_out = 48e3;     % 最終播放取樣率
fs_proc = 192e3;         % DSP 處理頻率

rx_len = floor(SR * Capture_Time);
decimation_factor = floor(SR / fs_proc);          % 960k -> 192k
decimation_audio = floor(fs_proc / fs_audio_out); % 192k -> 48k

%% 2. 初始硬體設定與狀態變數初始化
fprintf('=== YTTEK SDR AM 接收端 (低雜訊高振幅 v2) ===\n');

Ga = -20;                 % 初始 RX Gain (Ref Level)
target_mean = 0.35;       % 硬體 AGC 目標平均振幅 (略提高)
dc_val = 0;               % 包絡線 DC 追蹤
alpha_dc = 0.98;          % 較慢追蹤，避免音訊低頻抖動

audio_gain = 2.0;         % 音訊端 AGC 初始增益
audio_target_rms = 0.25;  % 音訊目標 RMS
alpha_audio_gain = 0.90;  % 音訊 AGC 平滑係數

% 設定初始硬體參數
try
    LO_CHANGE(0, Target_Freq_MHz, Target_Freq_MHz);
    set_RX_Ref_Level_ELSDR([0 Ga]);
catch ME
    warning('硬體初始化失敗: %s', ME.message);
end

%% 3. 濾波器設計與狀態預分配
% 3.1 抗混疊濾波器 (for 960k -> 192k)
[b_anti, a_anti] = butter(5, (fs_proc / 2) / (SR / 2), 'low');
z_anti = zeros(max(length(a_anti), length(b_anti)) - 1, 1);

% 3.2 通道濾波器: 解調前限頻，降低寬頻雜訊
% AM 音訊最高約 5~10 kHz，基頻包絡約落在低頻，因此先保留較窄頻寬
[b_ch, a_ch] = butter(6, 12e3 / (fs_proc / 2), 'low');
z_ch = zeros(max(length(a_ch), length(b_ch)) - 1, 1);

% 3.3 解調後高通: 去除殘餘 DC 與低頻漂移
[b_hp, a_hp] = butter(2, 80 / (fs_proc / 2), 'high');
z_hp = zeros(max(length(a_hp), length(b_hp)) - 1, 1);

% 3.4 解調後低通: 壓抑高頻雜訊
[b_lp, a_lp] = butter(6, 6e3 / (fs_proc / 2), 'low');
z_lp = zeros(max(length(a_lp), length(b_lp)) - 1, 1);

%% 4. 設定即時音訊播放與繪圖
try
    deviceWriter = audioDeviceWriter('SampleRate', fs_audio_out);
    hasAudioToolbox = true;
catch
    warning('找不到 Audio Toolbox，將使用 sound() 播放，可能有重疊或卡頓。');
    hasAudioToolbox = false;
end

hFig = figure('Name', '即時 AM 解調 v2 (關閉視窗以停止)', 'Color', 'w');
ax = axes('Parent', hFig);
hLine = plot(ax, nan, nan, 'b');
title(ax, '即時解調音訊'); xlabel(ax, '時間 (秒)'); ylabel(ax, '振幅');
ylim(ax, [-1 1]); grid on;

n_audio = floor(rx_len / (decimation_factor * decimation_audio));
t_plot = (0:n_audio - 1) / fs_audio_out;

%% 5. 連續接收與動態處理迴圈
fprintf('\n開始連續接收...\n');
fprintf('>>> 關閉「繪圖視窗」即可停止程式 <<<\n\n');

while ishandle(hFig)
    try
        %% --- A. 擷取訊號 ---
        rk = RX(1, rx_len);
        rk_col = rk.';

        %% --- B. 硬體端 AGC (慢速、平滑) ---
        rr_mean = mean(abs(rk_col));

        if abs(rr_mean - target_mean) > 0.05
            gain_diff = 10 * log10(target_mean / (rr_mean + 1e-6));
            gain_step = max(min(gain_diff, 2), -2); % 限制每次調整幅度

            Ga = Ga - gain_step;
            Ga = min(max(Ga, -50), 0);

            set_RX_Ref_Level_ELSDR([0 Ga]);
        end

        %% --- C. 降取樣到 DSP 頻率 ---
        [rk_filtered, z_anti] = filter(b_anti, a_anti, rk_col, z_anti);
        rx_proc = downsample(rk_filtered, decimation_factor);

        %% --- D. 解調前通道限頻 ---
        [rx_ch, z_ch] = filter(b_ch, a_ch, rx_proc, z_ch);

        %% --- E. AM 包絡線解調與 DC 移除 ---
        rx_env = abs(rx_ch);

        chunk_mean = mean(rx_env);
        dc_val = alpha_dc * dc_val + (1 - alpha_dc) * chunk_mean;
        rx_audio = rx_env - dc_val;

        %% --- F. 音訊頻帶整形 (高通 + 低通) ---
        [rx_audio, z_hp] = filter(b_hp, a_hp, rx_audio, z_hp);
        [rx_audio, z_lp] = filter(b_lp, a_lp, rx_audio, z_lp);

        %% --- G. 最終降取樣到 48k ---
        audio_out = downsample(rx_audio, decimation_audio);

        %% --- H. 音訊端 AGC + soft limiter ---
        audio_rms = sqrt(mean(audio_out .^ 2) + 1e-12);
        inst_gain = audio_target_rms / (audio_rms + 1e-9);
        inst_gain = min(max(inst_gain, 0.5), 8.0); % 允許更大增益，改善音量不足

        audio_gain = alpha_audio_gain * audio_gain + (1 - alpha_audio_gain) * inst_gain;
        audio_out = audio_out * audio_gain;

        % soft limiter: 抑制突波，避免破音
        audio_out = tanh(1.6 * audio_out);

        %% --- I. 播放 ---
        if hasAudioToolbox
            deviceWriter(audio_out);
        else
            sound(audio_out, fs_audio_out);
        end

        %% --- J. 更新畫面 ---
        set(hLine, 'XData', t_plot, 'YData', audio_out);
        title(ax, sprintf('即時解調音訊 v2 (Ga=%.1f dB, AudGain=%.2f)', Ga, audio_gain));
        drawnow limitrate;

    catch ME
        if ~ishandle(hFig)
            break;
        end
        warning('執行迴圈發生錯誤: %s', ME.message);
        pause(0.1);
    end
end

fprintf('\n停止接收，已釋放資源。\n');
if hasAudioToolbox
    release(deviceWriter);
end
