% --- 參數設定 ---
fs = 1e6;                 % 取樣率 (Sampling Rate) = 1 MHz
T = 1/fs;                 % 取樣週期
L = 10000;                % 訊號長度
t = (0:L-1)*T;            % 時間向量

fm = 5e3;                 % Message frequency = 5 kHz
fc = 0.1e6;               % Carrier frequency = 0.1 MHz (100 kHz)

% --- 1. 生成訊息訊號與載波 ---
mt = cos(2*pi*fm*t);      % m(t)
ct = cos(2*pi*fc*t);      % c(t)

% --- 2. DSB-SC 調變 ---
st = mt .* ct;            % s(t) = m(t) * c(t)

% --- 3. DSB-SC 解調 (Coherent Detection) ---
demod_raw = st .* ct;

% --- 4. FIR 低通濾波器 ---
N = 101;
fc_lpf = 20e3;
wc = 2 * pi * fc_lpf / fs; % 正規化角頻率
n = -(N-1)/2 : (N-1)/2;

% 計算 Sinc 函數與窗函數
h_ideal = sin(wc * n) ./ (pi * n);
h_ideal((N+1)/2) = wc / pi;
w = 0.54 - 0.46 * cos(2 * pi * (0:N-1) / (N-1)); % Hamming Window
h = h_ideal .* w;

% 執行卷積 (Convolution)
demod_signal_raw = conv(demod_raw, h, 'same');
demod_signal = demod_signal_raw * 2; % 補償相干解調造成的振幅減半

% --- 5. 頻譜分析 (FFT) ---
f = fs*(0:(L/2))/L;       % 頻率軸 (0 到 500kHz)
MT = abs(fft(mt)/L);
ST = abs(fft(st)/L);
DEMOD = abs(fft(demod_signal)/L);

% --- 6. 繪圖 ---
figure('Name', 'DSB-SC Simulation (fs=1MHz, fc=0.1MHz)', 'Color', 'w');

% A. 時域圖 (看前 1000 個點，約 1ms)
subplot(3,1,1);
plot(t(1:1000)*1e3, mt(1:1000), 'b', 'LineWidth', 1, 'DisplayName', 'Message'); hold on;
plot(t(1:1000)*1e3, st(1:1000), 'r', 'Color', [1 0 0 0.4], 'DisplayName', 'DSB-SC');
title('時域訊號 (Time Domain)');
xlabel('時間 (ms)');
legend; grid on;

% B. 頻域圖 (觀察載波與側帶)
subplot(3,1,2);
plot(f/1e3, 2*ST(1:L/2+1), 'r', 'LineWidth', 1.5);
title('DSB-SC 調變後頻譜 (Centered at 100kHz)');
xlabel('頻率 (kHz)');
xlim([80 120]); % 放大看載波附近的側帶
grid on;

% C. 解調結果對比 (加上相位補償)
subplot(3,1,3);
delay = (N-1)/2; % FIR 延遲
% 繪圖時對齊延遲：Original 往前縮，Demodulated 往後移
plot(t(1:1000-delay)*1e3, mt(1:1000-delay), 'b', 'LineWidth', 2, 'DisplayName', 'Original'); hold on;
plot(t(1:1000-delay)*1e3, demod_signal(delay+1:1000), 'r--', 'LineWidth', 1.5, 'DisplayName', 'Demodulated');
title('解調結果對比');
xlabel('時間 (ms)');
legend; grid on;