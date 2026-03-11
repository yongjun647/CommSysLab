%--- 1. 讀取音訊檔案 ---
fprintf('=== MP3 DSB-SC 音樂電台 ===\n');
mp3_filename = 'music.mp3';

% 檢查檔案是否存在
if ~isfile(mp3_filename)
    error('錯誤：找不到檔案 %s', mp3_filename);
end

% 讀取音訊檔案
[y, fs_audio] = audioread(mp3_filename);

% 若為雙聲道立體聲，取平均轉成單聲道 (Mono)
if size(y, 2) > 1
    y = mean(y, 2);
end

% 根據 Loop_Duration 計算取樣點數並裁切
Loop_Duration = 20;
samples_Duration = floor(Loop_Duration * fs_audio);
y = y(1:min(end, samples_Duration));

fprintf('成功讀取音訊，裁切長度：%.2f 秒\n', length(y)/fs_audio);

% --- 2. 參數與重採樣 ---
fs = 1e6;                 % 通訊採樣率: 1 MHz
fc = 0.1e6;               % 載波頻率: 0.1 MHz

fprintf('正在進行重採樣至 100MHz... (請稍候)\n');
% 將音訊提升到通訊採樣率
mt = resample(y, fs, fs_audio).';
L = length(mt);
t = (0:L-1)/fs;

% --- 3. 調變 ---
ct = cos(2*pi*fc*t);
st = mt .* ct;            % DSB-SC 訊號

% --- 4. 解調與 FIR 濾波 ---
demod_raw = st .* ct;

% FIR 濾波器設計
N = 101;
fc_lpf = 15e3;            % 音訊截止頻率 15kHz (過濾通訊雜訊)
wc = 2 * pi * fc_lpf / fs;
n = -(N-1)/2 : (N-1)/2;
h = (sin(wc*n)./(pi*n)) .* hamming(N)';
h((N+1)/2) = wc/pi;

fprintf('正在進行卷積濾波...\n');
demod_signal_raw = conv(demod_raw, h, 'same');
demod_signal = demod_signal_raw * 2;

% --- 5. 繪圖 (畫一小段就好，避免介面卡死) ---
figure('Name', '10s Audio DSB Simulation', 'Color', 'w');

% 時域：顯示第 1 秒附近的 5 毫秒片段
view_range = round(1.0 * fs) : round(1.005 * fs);

subplot(2,1,1);
plot(t(view_range)*1e3, mt(view_range), 'b', 'LineWidth', 1.5); hold on;
plot(t(view_range)*1e3, st(view_range), 'r', 'Color', [1 0 0 0.2]);
title('時域訊號放大 (1.0s - 1.005s)');
xlabel('時間 (ms)');
legend('原始音訊', 'DSB-SC 調變');
grid on;

% 頻域：分析前 0.1 秒的頻譜
L_fft = 2^18;
ST_FFT = abs(fft(st(1:L_fft), L_fft)/L_fft);
f = fs*(0:L_fft/2)/L_fft;

subplot(2,1,2);
plot(f/1e6, 2*ST_FFT(1:L_fft/2+1));
title('DSB-SC 頻譜中心 (10MHz)'); 
xlabel('頻率 (MHz)'); 
xlim([fc/1e6 - 0.05, fc/1e6 + 0.05]);
grid on;

% --- 6. 播放音樂 ---
fprintf('正在還原音訊以供播放...\n');
audio_out = resample(demod_signal, fs_audio, fs);

% 正規化音量防止爆音
audio_out = audio_out / max(abs(audio_out));

% 播放解調後的聲音
fprintf('準備播放解調後的音樂...\n');
sound(audio_out, fs_audio);