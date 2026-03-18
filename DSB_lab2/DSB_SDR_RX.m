%% SDR MP3 Player (DSB-SC 零中頻直驅版 - 極簡純低通濾波接收)
% 功能：設定 433MHz LO -> 擷取基頻 IQ -> 純低通濾波 -> 直接提取實部播放
clc; clear; close all;

%% 1. 參數設定
SR = 960e3;              % SDR 硬體取樣率 0.96 MHz
Target_Freq_MHz = 433;   % 接收中心頻率 (必須與 TX 完全相同)
Capture_Time = 15;       % 錄製 15 秒
fs_audio_out = 48e3;     % 最終播放的音訊取樣率 (48 kHz)
fs_proc = 192e3;         % DSP 處理頻率

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

% 【關鍵】因為沒有做相位旋轉對齊，我們直接強取 I 通道 (實部) 當作音樂
audio_demod = real(rx_filtered);

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