
%% SDR MP3 接收端 - 動態增益與 abs() 解調
clc; clear; close all;

%% 1. 參數設定
SR = 960e3;              % 軟體基頻取樣率
Target_Freq_MHz = 433;   % 接收中心頻率
Capture_Time = 5;        % 每次擷取秒數 (調整增益時建議短一點，確定後再加長)
fs_audio_out = 48e3;     % 最終播放取樣率
fs_proc = 192e3;         % DSP 處理頻率
Ga = -10;                % 初始 RX Gain (Ref Level)
stop_sign = 0.5;         % 目標最大振幅
rr_max = 0;              % 用來儲存當前最大振幅
rx_len = SR * Capture_Time;

%% 2. 初始化與動態增益調整 (AGC Mean 版本)
fprintf('=== YTTEK SDR AM 接收端 (AGC Mean ) ===\n');

% 設定平均值的目標 (若期望峰值 0.5, 平均值約設在 0.2~0.3 較穩定)
target_mean = 0.25;
rr_mean = 0;
iter = 0;
max_iter = 8; % 達到設定迴圈上限也停

while abs(rr_mean - target_mean) > 0.05
    iter = iter + 1;
    if iter > max_iter
        fprintf('達到最大嘗試次數，停止調整並進入解調。\n');
        break;
    end
    
    try
        % 硬體控制指令
        LO_CHANGE(0, Target_Freq_MHz, Target_Freq_MHz);
        set_RX_Ref_Level_ELSDR([0 Ga]);
        
        fprintf('Iter %d: 目前 Ga = %.2f, 擷取中... ', iter, Ga);
        rk = RX(1, rx_len);
        
        % --- 使用平均絕對值 (Mean Absolute Value) ---
        rr_mean = mean(abs(rk));
        fprintf('當前平均振幅: %.4f (目標: %.2f)\n', rr_mean, target_mean);
        
        % 如果誤差太大則調整
        if abs(rr_mean - target_mean) > 0.05
            % 計算步長 (使用對數方式計算增益差)
            step = 10 * log10(target_mean / (rr_mean + 1e-6));
            Ga = Ga - step;
            
            % 硬體邊界保護
            if Ga > 0, Ga = 0; end
            
            % 觸底直接終止
            if Ga < -50
                error('AGC_FATAL: 增益已達極限 (-50) 。');
            end
        end

    catch ME
        % 如果是我們自定義的錯誤則直接拋出，不進行重試
        if contains(ME.message, 'AGC_FATAL')
            rethrow(ME);
        end
        warning('硬體異常: %s, 正在重試...', ME.message);
        pause(0.5);
    end
end
fprintf('增益調整完成，最終接收端增益為 : %.2f。\n', Ga);

%% 3. 降取樣處理 (downsample)
rk_col = rk.';
decimation_factor = floor(SR / fs_proc);

% 設計抗混疊濾波器 (Anti-aliasing filter)
[b_anti, a_anti] = butter(5, (fs_proc/2) / (SR/2), 'low');
rk_filtered = filter(b_anti, a_anti, rk_col);

% 執行降取樣
rx_baseband = downsample(rk_filtered, decimation_factor);

%% 4. AM 解調
rx_env = abs(rx_baseband);

% --- Step D: 移除直流並過濾音訊雜訊 ---
rx_audio_raw = rx_env - mean(rx_env);
[b_audio, a_audio] = butter(5, 10e3 / (fs_proc/2), 'low');
rx_audio_filtered = filter(b_audio, a_audio, rx_audio_raw);

%% 5. 重取樣與音訊輸出
fprintf('正在輸出音訊...\n');

audio_out = resample(rx_audio_filtered, fs_audio_out, fs_proc);

% 正規化
if max(abs(audio_out)) > 0
    audio_out = audio_out / max(abs(audio_out));
end

% 播放
soundsc(audio_out, fs_audio_out);

%% 6. 畫圖觀察
figure('Name', 'AM 解調波形分析', 'Color', 'w');
t_plot = (0:length(audio_out)-1) / fs_audio_out;
plot(t_plot, audio_out, 'b');
title(['解調後的音訊 (Ga = ', num2str(Ga), ')']);
xlabel('時間 (秒)'); ylabel('振幅');
grid on; axis tight;


