%% SDR MP3 接收端 - 連續動態增益與即時解調 (Continuous & Dynamic)
clc; clear; close all;

%% 1. 參數設定
SR = 960e3;              % 軟體基頻取樣率
Target_Freq_MHz = 433;   % 接收中心頻率
Capture_Time = 0.2;      % 每次擷取秒數 (縮短至 0.2 秒以達到低延遲即時感)
fs_audio_out = 48e3;     % 最終播放取樣率
fs_proc = 192e3;         % DSP 處理頻率

rx_len = floor(SR * Capture_Time);
decimation_factor = floor(SR / fs_proc);        % 960k -> 192k (降取樣 5)
decimation_audio = floor(fs_proc / fs_audio_out); % 192k -> 48k (降取樣 4)

%% 2. 初始硬體設定與狀態變數初始化
fprintf('=== YTTEK SDR AM 接收端 (動態連續版) ===\n');

Ga = -20;                % 初始 RX Gain (Ref Level)
target_mean = 0.25;      % AGC 目標平均振幅
dc_val = 0;              % 直流偏置初始值 (動態更新用)
alpha_dc = 0.95;         % 直流濾波器平滑係數 (0~1，越大越平滑)

% 設定初始硬體參數
try
    LO_CHANGE(0, Target_Freq_MHz, Target_Freq_MHz);
    set_RX_Ref_Level_ELSDR([0 Ga]);
catch ME
    warning('硬體初始化失敗: %s', ME.message);
end

%% 3. 濾波器設計與狀態預分配 (避免爆音的關鍵)
% 3.1 射頻抗混疊濾波器
[b_anti, a_anti] = butter(5, (fs_proc/2) / (SR/2), 'low');
z_anti = zeros(max(length(a_anti), length(b_anti))-1, 1); % 初始狀態

% 3.2 音訊低通濾波器 (兼作音訊抗混疊，10kHz Cutoff)
[b_audio, a_audio] = butter(5, 10e3 / (fs_proc/2), 'low');
z_audio = zeros(max(length(a_audio), length(b_audio))-1, 1); % 初始狀態

%% 4. 設定即時音訊播放與繪圖
% 建議使用 Audio Toolbox 的 audioDeviceWriter 以獲得不卡頓的串流體驗
try
    deviceWriter = audioDeviceWriter('SampleRate', fs_audio_out);
    hasAudioToolbox = true;
catch
    warning('找不到 Audio Toolbox，將使用基礎 sound() 播放，可能會有些許重疊或卡頓。');
    hasAudioToolbox = false;
end

% 建立繪圖視窗 (利用關閉視窗來中斷迴圈)
hFig = figure('Name', '即時 AM 解調 (關閉視窗以停止)', 'Color', 'w');
ax = axes('Parent', hFig);
hLine = plot(ax, nan, nan, 'b');
title(ax, '即時解調音訊'); xlabel(ax, '時間 (秒)'); ylabel(ax, '振幅');
ylim(ax, [-1 1]); grid on;
t_plot = (0:(rx_len/(decimation_factor*decimation_audio))-1) / fs_audio_out;

%% 5. 連續接收與動態處理迴圈
fprintf('\n開始連續接收...\n');
fprintf('>>> 關閉「繪圖視窗」即可停止程式 <<<\n\n');

while ishandle(hFig)
    try
        %% --- A. 擷取訊號 ---
        rk = RX(1, rx_len); 
        rk_col = rk.';
        
        %% --- B. 動態增益控制 (AGC) ---
        rr_mean = mean(abs(rk_col));
        
        % 若平均值偏離目標，則微調增益
        if abs(rr_mean - target_mean) > 0.05
            % 計算建議步長
            gain_diff = 10 * log10(target_mean / (rr_mean + 1e-6));
            
            % 限制單次調整幅度 (例如最大 +/- 3 dB)，讓 AGC 平滑運作，避免聲音忽大忽小
            gain_step = max(min(gain_diff, 3), -3); 
            
            Ga = Ga - gain_step;
            
            % 增益硬體邊界保護
            if Ga > 0, Ga = 0; end
            if Ga < -50, Ga = -50; end
            
            % 即時套用新增益
            set_RX_Ref_Level_ELSDR([0 Ga]);
        end
        
        %% --- C. 降取樣處理 (射頻段) ---
        % 加入 z_anti 傳遞濾波器狀態
        [rk_filtered, z_anti] = filter(b_anti, a_anti, rk_col, z_anti);
        rx_baseband = downsample(rk_filtered, decimation_factor);
        
        %% --- D. AM 包絡線解調 ---
        rx_env = abs(rx_baseband);
        
        % 平滑動態去直流 (Exponential Moving Average)
        chunk_mean = mean(rx_env);
        dc_val = alpha_dc * dc_val + (1 - alpha_dc) * chunk_mean;
        rx_audio_raw = rx_env - dc_val;
        
        %% --- E. 音訊濾波與最終降取樣 ---
        % 加入 z_audio 傳遞濾波器狀態
        [rx_audio_filtered, z_audio] = filter(b_audio, a_audio, rx_audio_raw, z_audio);
        
        % 直接使用 downsample 替代 resample，徹底消除實時處理的邊緣失真
        audio_out = downsample(rx_audio_filtered, decimation_audio);
        
        %% --- F. 正規化與播放 ---
        % 溫和的音量動態壓縮/正規化 (避免突波導致聲音破音)
        max_val = max(abs(audio_out));
        if max_val > 1.2
            audio_out = audio_out / max_val;
        else
            % 固定放大比例，保留音樂動態範圍
            audio_out = audio_out * 0.8; 
        end
        
        if hasAudioToolbox
            deviceWriter(audio_out); % 平滑串流播放
        else
            sound(audio_out, fs_audio_out); % 基礎播放 (堪用方案)
        end
        
        %% --- G. 更新畫面 ---
        set(hLine, 'XData', t_plot, 'YData', audio_out);
        title(ax, sprintf('即時解調音訊 (當前硬體增益 Ga = %.1f dB)', Ga));
        drawnow limitrate; % 限制畫面更新頻率，確保音訊運作順暢
        
    catch ME
        % 忽略因為關閉視窗導致的繪圖錯誤
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