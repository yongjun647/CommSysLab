%% SDR MP3 Player (DSB-SC 零中頻直驅版 - 極簡純低通濾波接收)
% 功能：設定 433MHz LO -> 擷取基頻 IQ -> 純低通濾波 -> 直接提取實部播放
clc; clear; close all;

%% 1. 參數設定
SR = 960e3;             % SDR 硬體取樣率 1.92 MHz
Target_Freq_MHz = 433;  % 接收中心頻率 (必須與 TX 完全相同)
Capture_Time = 15;      % 錄製 15 秒
fs_audio_out = 48e3;    % 最終播放的音訊取樣率 (48 kHz)
fs_proc = 192e3;        % DSP 處理頻率

%% 2. 啟動 SDR 接收硬體
fprintf('=== SDR MP3 極簡接收端 ===\n');
fprintf('正在擷取 %d 秒的空中訊號...\n', Capture_Time);

LO_CHANGE(0, Target_Freq_MHz, Target_Freq_MHz);
set_RX_Ref_Level_ELSDR([0 -10]);

% 擷取第 1 個 Row 的資料 (1 x N 橫向量)
rx_iq = RX(1, SR * Capture_Time);
fprintf('擷取完成！\n');

%% 3. 資料轉置與降取樣
% 轉置為 N x 1 的 Column Vector 以利濾波器處理
if size(rx_iq, 1) == 1
    rx_iq = rx_iq.';
end

% 降取樣
decimation_factor = floor(SR / fs_proc);
rx_baseband = downsample(rx_iq, decimation_factor);

%% 4. 純低通濾波 (無 Costas Loop)
fprintf('進行低通濾波...\n');

% 設計低通濾波器濾除高頻雜訊 (15 kHz 音樂頻寬)
cutoff_freq = 15e3;
[b, a] = butter(5, cutoff_freq / (fs_proc/2));

% 直接對複數基頻訊號進行濾波
rx_filtered = filtfilt(b, a, rx_baseband);

% --- 解決互傳同步的 Costas Loop 演算法 ---
N = length(rx_filtered);
audio_demod = zeros(1, N);
phase_est = 0;      % 初始相位估測
freq_offset = 0;    % 初始頻率偏移估測

% 迴路濾波器參數 (PI Controller)
% 提示：這兩個參數控制鎖相的速度，可能需要根據實際 SDR 狀況微調
alpha = 0.05;  % 比例增益 (控制當下相位的修正力道)
beta = 0.001;  % 積分增益 (控制頻率偏移的追蹤力道)

fprintf('啟動 Costas Loop 進行相位與頻率追蹤...\n');

for k = 1:N
    % 1. 利用當前的估測相位，把接收訊號轉回來
    sample_sync = rx_filtered(k) * exp(-1j * phase_est);

    % 【新增】記錄同步後的複數訊號
    rx_sync(k) = sample_sync;
    
    % 2. 提取對齊後的 I (實部) 與 Q (虛部)
    I = real(sample_sync);
    Q = imag(sample_sync);
    
    % 3. 儲存修正好的 I 通道當作音樂輸出
    audio_demod(k) = I;
    
    % 4. 計算相位誤差 (Error Detector)
    % DSB-SC 的經典誤差計算：取 I 的符號乘上 Q
    err = sign(I) * Q;
    
    % 5. 更新下一個時間點的頻率與相位 (Loop Filter)
    freq_offset = freq_offset + beta * err;
    phase_est = phase_est + freq_offset + alpha * err;
    
    % 限制相位在 -pi 到 pi 之間，避免數值溢位
    phase_est = wrapToPi(phase_est);
end

%% --- 繪圖證明：theta 影響消失的視覺化 ---
figure('Name', '相位同步 (Costas Loop) 效果比較', 'Color', 'w', 'Position', [100, 100, 1000, 400]);

% 1. 第一張圖：IQ 星系圖 (Constellation Diagram)
subplot(1, 2, 1);
% 為了避免點數太多卡頓，每 10 個點取 1 個點來畫 (Downsample for plotting)
plot_step = 10;
% 同步前：因為 theta 隨時間亂轉，IQ 訊號會散佈在整個圓環上
scatter(real(rx_filtered(1:plot_step:end)), imag(rx_filtered(1:plot_step:end)), 5, 'r', 'filled', 'MarkerFaceAlpha', 0.2);
hold on;
% 同步後：Costas loop 將相位鎖定，能量全部被壓回 I 通道 (X軸)，Q 通道趨近於 0
scatter(real(rx_sync(1:plot_step:end)), imag(rx_sync(1:plot_step:end)), 5, 'b', 'filled', 'MarkerFaceAlpha', 0.2);

title('IQ 散佈圖 (Constellation)');
xlabel('I 通道 (實部)'); ylabel('Q 通道 (虛部)');
legend('同步前 (相位亂轉)', '同步後 (鎖定於 I 軸)', 'Location', 'best');
grid on; axis square;
% 設定座標軸範圍確保視覺為正方形
max_val = max(abs(rx_filtered));
xlim([-max_val max_val]); ylim([-max_val max_val]);

% 2. 第二張圖：時域波形 (Time Domain) 比較
subplot(1, 2, 2);
% 只取一小段時間 (例如 0.05 秒) 來觀察波形細節
samples_to_plot = round(0.05 * fs_proc); 
t_plot = (0:samples_to_plot-1) / fs_proc;

% 同步前：直接取實部，會看到訊號因為頻率偏移而產生忽大忽小 (Fading 包絡線)
plot(t_plot, real(rx_filtered(1:samples_to_plot)), 'r', 'LineWidth', 1);
hold on;
% 同步後：還原出完整、振幅穩定且無衰減的音樂波形
plot(t_plot, real(rx_sync(1:samples_to_plot)), 'b', 'LineWidth', 1);

title('接收端時域波形比較 (前 0.05 秒)');
xlabel('時間 (秒)'); ylabel('振幅');
legend('同步前 (直接取實部有衰減)', '同步後 (完整還原)', 'Location', 'best');
grid on;

%% 5. 播放與繪圖
% 重採樣回標準音訊格式 (48 kHz)
audio_out = resample(audio_demod, fs_audio_out, fs_proc);

% 正規化音量防止喇叭破音
audio_out = audio_out / max(abs(audio_out));

fprintf('播放極簡解調的音樂！\n');
soundsc(audio_out, fs_audio_out);

% 畫圖觀察
figure('Name', '極簡接收端波形分析', 'Color', 'w');
t_plot = (0:length(audio_out)-1) / fs_audio_out;
plot(t_plot, audio_out, 'k');
title('解調音訊波形');
xlabel('時間 (秒)'); ylabel('振幅'); grid on;