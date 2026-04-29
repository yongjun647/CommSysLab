%% YTPC1002C01 SDR - FDM WAV 接收端 (1.92MHz)
clc; clear; close all;

%% 1. 參數設定
Fs = 1.92e6;            % 取樣率必須與 TX 完全一致 (1.92 MHz)
Ts = 1/Fs;
Target_Freq_MHz = 433;  % 接收中心頻率 (MHz)
Capture_Duration = 15;  % 一次擷取 15 秒的訊號

f_sub1 = 20e3;          % 子載波 1: 20 kHz
f_sub2 = 100e3;         % 子載波 2: 100 kHz

%% 2. SDR設定與接收
fprintf('=== SDR FDM WAV 接收端 (1.92MHz) ===\n');
disp('確保 YTPC1002C01 RX 端設定正確...');

% 設定接收頻率與參考準位
LO_CHANGE(0, Target_Freq_MHz, Target_Freq_MHz);
set_RX_Ref_Level_ELSDR([0 -10]); % 設定 RX1 參考準位為 -10 dBm

data_len = round(Capture_Duration * Fs); % 19,200,000 個點
t_sdr = (0:data_len-1) * Ts;             % 建立 SDR 時間軸 (橫向量)

fprintf('正在接收 %d 秒的射頻訊號，請稍候...\n', Capture_Duration);
% 擷取單天線 (RX1) 指定長度的資料
rx_raw = RX(1, data_len);
disp('接收完成！');

%% 3. 設計 LPF 與訊號解調
disp('正在進行解調與低通濾波...');

% 設計基頻低通濾波器 (截止頻率 15 kHz，保留音訊，濾除高頻雜訊與相鄰頻道)
[b_base, a_base] = butter(3, 15e3/(Fs/2), 'low');

% --- 音軌 1 解調 (20 kHz) ---
% 1. 頻率搬移 (將 20kHz 降回 DC)
s1_base = rx_raw .* exp(-1j * 2 * pi * f_sub1 * t_sdr);
% 2. 對 AM 做 Envelope Detection (取絕對值) 並通過低通濾波器
s1_demod = abs(filtfilt(b_base, a_base, s1_base));
% 3. 移除 AM 的直流偏置 (DC Offset)
s1_demod = s1_demod - mean(s1_demod);

% --- 音軌 2 解調 (100 kHz) ---
% 1. 頻率搬移 (將 100kHz 降回 DC)
s2_base = rx_raw .* exp(-1j * 2 * pi * f_sub2 * t_sdr);
% 2. 對 AM 做 Envelope Detection (取絕對值) 並通過低通濾波器
s2_demod = abs(filtfilt(b_base, a_base, s2_base));
% 3. 移除 AM 的直流偏置 (DC Offset)
s2_demod = s2_demod - mean(s2_demod);

%% 4. 音訊降頻與播放
disp('正在轉換回音訊取樣率...');
fs_audio = 44100; % 標準 WAV 播放取樣率
audio_len = round(Capture_Duration * fs_audio);
t_audio = (0:audio_len-1) / fs_audio;

% 使用 interp1 將 1.92MHz 的解調訊號降頻回 44.1kHz
audio_out1 = interp1(t_sdr, s1_demod, t_audio, 'linear', 'extrap');
audio_out2 = interp1(t_sdr, s2_demod, t_audio, 'linear', 'extrap');

%audiowrite('demodulated_audio1.wav', audio_out1, 44100);
%audiowrite('demodulated_audio2.wav', audio_out2, 44100);

disp('正在繪製頻譜與波形...');
figure('Name', 'SDR 1.92MHz RX Result', 'Color', 'w', 'Position', [100 100 900 600]);

% 繪製接收到的基頻頻譜
L_fft = min(length(rx_raw), 2^18); % 取適當長度畫 FFT 加快速度
f = (-L_fft/2 : L_fft/2-1) * (Fs/L_fft);
P_rx = fftshift(abs(fft(rx_raw(1:L_fft))))/L_fft;
plot(f/1e3, 20*log10(P_rx + eps), 'b', 'LineWidth', 1);
grid on; xlim([-150 150]); ylim([-150 0]);
title('接收端之基頻 FDM 頻譜 ( 20kHz 與 100kHz 雙峰)');
xlabel('頻率 (kHz)'); ylabel('強度 (dB)');

% 立體聲播放 (轉成直向量合併放入 sound)
disp('準備播放解調後的立體聲音訊 (左耳: 音軌1, 右耳: 音軌2)');
% 分別對左、右聲道做標準化，確保兩邊音量一致
audio_out1 = audio_out1 / max(abs(audio_out1)) * 0.8;
audio_out2 = audio_out2 / max(abs(audio_out2)) * 0.8;

stereo_out = [audio_out1(:), audio_out2(:)];
sound(stereo_out, fs_audio);

disp('測試完成！');