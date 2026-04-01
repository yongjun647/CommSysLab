%% SDR MP3 接收端 - 連續動態增益調整 (Continuous AGC)
clc; clear; close all;

%% 1. 參數設定
SR = 960e3;               % 軟體基頻取樣率 [cite: 88]
Target_Freq_MHz = 433;    % 接收中心頻率 [cite: 89]
Capture_Time = 1;       % ★ 修改：縮短每次擷取秒數以提高動態響應速度 (例如 0.5 秒)
fs_audio_out = 48e3;      % 最終播放取樣率
fs_proc = 192e3;          % DSP 處理頻率 [cite: 91]
Ga = -10;                 % 初始 RX Gain (Ref Level) [cite: 92]
rx_len = SR * Capture_Time; 

target_mean = 0.25;       % 設定平均值的目標 

% ★ 優化：預先設計濾波器以節省迴圈內的運算時間
decimation_factor = floor(SR / fs_proc); 
[b_anti, a_anti] = butter(5, (fs_proc/2) / (SR/2), 'low');
[b_audio, a_audio] = butter(5, 10e3 / (fs_proc/2), 'low');
%% 2. 初始化 SDR 與即時圖表
fprintf('=== YTTEK SDR AM 接收端(連續動態 AGC) ===\n');
try
    LO_CHANGE(0, Target_Freq_MHz, Target_Freq_MHz); 
    set_RX_Ref_Level_ELSDR([0 Ga]); 
catch
    warning('硬體初始化失敗，請確認設備連線。');
end

% 建立動態更新的圖表
fig = figure('Name', 'AM 即時解調與動態增益觀察', 'Color', 'w');
% 初始化一條空載的線條
h_plot = plot(zeros(1, fs_audio_out * Capture_Time), 'b');
xlabel('取樣點'); ylabel('振幅');
grid on; ylim([-1.2 1.2]);

fprintf('開始連續接收... (請關閉圖表視窗或按 Ctrl+C 停止程式)\n');

%% 3. 連續接收與動態增益迴圈
% 當圖表未被關閉時，持續進行接收與解調
while ishandle(fig) 
    try
        % --- 步驟 A：擷取訊號 ---
        rk = RX(1, rx_len); 
     
        % --- 步驟 B：動態增益調整 (即時 AGC) ---
        rr_mean = mean(abs(rk)); 
        
        % 計算下一幀的增益步長
        if rr_mean > 0
            % ★ 修改：加入 0.5 的平滑係數，避免距離改變時增益跳動過於劇烈
            step = 10 * log10(target_mean / (rr_mean + 1e-6)); 
            Ga = Ga + (step * 0.5); 
        end
        
        % 硬體邊界保護 [cite: 131, 132]
        if Ga > 0, Ga = 0; end 
        if Ga < -50, Ga = -50; end
        
        % 套用新增益至硬體 (將在下一次擷取時生效)
        set_RX_Ref_Level_ELSDR([0 Ga]);
        fprintf('平均振幅: %.4f | 即時動態增益 Ga: %.2f dB\n', rr_mean, Ga);
        
        % --- 步驟 C：降取樣與 AM 解調 ---
        rk_col = rk.'; 
        rk_filtered = filter(b_anti, a_anti, rk_col); 
        rx_baseband = downsample(rk_filtered, decimation_factor); 
        
        rx_env = abs(rx_baseband); 
        rx_audio_raw = rx_env - mean(rx_env); 
        rx_audio_filtered = filter(b_audio, a_audio, rx_audio_raw); 
        
        % --- 步驟 D：重取樣與播放 ---
        audio_out = resample(rx_audio_filtered, fs_audio_out, fs_proc);
        
        % 正規化音訊以確保輸出給喇叭的音量穩定
        max_val = max(abs(audio_out));
        if max_val > 0
            audio_out = audio_out / max_val; 
        end
        
        % 播放音訊
        % (注意：MATLAB 標準函式在迴圈中連續呼叫可能會有些微延遲縫隙)
        sound(audio_out, fs_audio_out); 
        
        % --- 步驟 E：更新圖表 ---
        % 只更新 Y 軸數據，比重新 plot() 效能更好
        set(h_plot, 'YData', audio_out);
        title(sprintf('即時解調音訊 (動態增益 Ga = %.2f dB)', Ga));
        drawnow; % 立即刷新圖表畫面
        
    catch ME
        warning('執行異常: %s', ME.message);
        pause(0.5); % 若發生錯誤，稍作停頓避免洗頻
    end
end

fprintf('圖表已關閉，接收結束。\n');