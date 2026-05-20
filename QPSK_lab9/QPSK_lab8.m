%% QPSK 模擬
clc; clear; close all;

%% 1. 參數設定 (System Parameters)
SR = 122.88e6;             % 取樣率
Upsampling_Factor = 64;    % 每個 Symbol 的取樣點數
Rolloff = 0.5;             % RRC Filter Rolloff
FilterSpan = 64;           % Filter span

% Frame 參數
PayloadLength_Bits = 174;
HeaderLength_Bits = 26;

%% 2. 模擬發射端
%% A. 產生發射資料
barker_13 = [1 1 1 1 1 0 0 1 1 0 1 0 1]';
header_bits = [barker_13; barker_13];

User_Message = 'Hello World.'; % 任意長度文字
msg_ascii = double(User_Message);
msg_bits = de2bi(msg_ascii, 7, 'left-msb')';
msg_bits = msg_bits(:);

num_random_bits = 174 - length(msg_bits);
if num_random_bits < 0, error('訊息過長'); end
rand_bits = randi([0 1], num_random_bits, 1);
payload_raw = [msg_bits; rand_bits];

scrambler = comm.Scrambler(2, [1 1 1 0 1], 'InitialConditions', [0 0 0 0]);
payload_scrambled = scrambler(payload_raw);
tx_bits = [header_bits; payload_scrambled];

% [加入保護機制: 自動補零確保 bit 數為偶數]
if mod(length(tx_bits), 2) ~= 0
    tx_bits = [tx_bits; 0];
end
FrameLength_Bits = length(tx_bits); % 動態更新正確長度

%% B. 調變與濾波
bits_reshaped = reshape(tx_bits, 2, []).';
sym_idx = bits_reshaped(:, 1) * 2 + bits_reshaped(:, 2);
lut = [exp(1j*pi/4); exp(1j*3*pi/4); exp(1j*7*pi/4); exp(1j*5*pi/4)];
tx_symbols = lut(sym_idx + 1);

rrc_filter = rcosdesign(Rolloff, FilterSpan, Upsampling_Factor, 'sqrt');
I_baseband = upfirdn(real(tx_symbols), rrc_filter, Upsampling_Factor);
Q_baseband = upfirdn(imag(tx_symbols), rrc_filter, Upsampling_Factor);

% DAC 限幅 (0.8)
scale_factor = max(abs([I_baseband; Q_baseband]));
tx_baseband = ((I_baseband / scale_factor) + 1j * (Q_baseband / scale_factor)) * 0.8;

% C. 模擬通道 (加入未知延遲、相位偏移與雜訊)
SNR_dB = 15;
Actual_Delay_Samples = randi([1000, 3000]); % 模擬訊號抵達前的空白時間 (Time Offset)
Actual_Phase_Offset = randi([0, 359]);      % 模擬未知的相位偏移 (Phase Offset)

% 組合出一條長長的接收波形 (前面雜訊 + 訊號 + 後面雜訊)
rx_signal = [zeros(Actual_Delay_Samples, 1); tx_baseband; zeros(2000, 1)];
rx_signal = awgn(rx_signal, SNR_dB, 'measured');
rx_signal = rx_signal * exp(-1j * deg2rad(Actual_Phase_Offset)); % 加入相位旋轉

% 移除直流偏移
rx_signal = rx_signal - mean(rx_signal);

%% 3. 脈衝整形濾波 (RRC Matched Filter)
rx_filtered = conv(rx_signal, rrc_filter, 'same');

%% 4. Frame 同步 (Frame Synchronization)
header_sym_idx = header_bits(1:2:end)*2 + header_bits(2:2:end);
header_symbols = lut(header_sym_idx + 1);
header_waveform = zeros(length(header_symbols) * Upsampling_Factor, 1);
header_waveform(1:Upsampling_Factor:end) = header_symbols;
header_waveform = conv(header_waveform, rrc_filter, 'same');
L_header = length(header_waveform);

matched_coeff = flip(conj(header_waveform));
rx_corr = filter(matched_coeff, 1, rx_filtered);
window_ones = ones(L_header, 1);
rx_power = abs(rx_filtered).^2;
rx_energy_moving = filter(window_ones, 1, rx_power);

header_energy_const = sum(abs(header_waveform).^2);
timing_metric = (abs(rx_corr).^2) ./ (rx_energy_moving * header_energy_const + 1e-10);

[max_metric, peak_idx] = max(timing_metric);
Sync_Threshold = 0.4;

fprintf('1. [時間同步] 最大指標 (Metric): %.4f\n', max_metric);
if max_metric < Sync_Threshold
    warning('同步失敗！指標過低，可能是純雜訊或未收到訊號。');
end

%% 步驟三：同步處理
start_idx = peak_idx - L_header + 1;
if start_idx < 1, start_idx = 1; end
samples_per_frame = (FrameLength_Bits / 2) * Upsampling_Factor;

if start_idx + samples_per_frame > length(rx_filtered)
    warning('Frame 尾端超出接收範圍，截斷處理。');
    samples_per_frame = length(rx_filtered) - start_idx;
end

frame_signal_oversampled = rx_filtered(start_idx : start_idx + samples_per_frame - 1);
fprintf('  -> 偵測到 Frame 起點 Index: %d\n', start_idx);

%% 5. 下取樣與靜態相位校正 (Static Phase Correction)
frame_symbols_raw = frame_signal_oversampled(1 : Upsampling_Factor : end);

rx_header_syms = frame_symbols_raw(1 : length(header_symbols));
phase_diff_vec = angle(rx_header_syms .* conj(header_symbols));
estimated_phase_error = mean(phase_diff_vec);

fprintf('2. [相位同步] 偵測到靜態相位偏移: %.2f 度\n', estimated_phase_error * 180/pi);
rx_symbols_sync = frame_symbols_raw * exp(-1j * estimated_phase_error);

%% 步驟四：解調過程
%% 6. 解調 (Demodulation) - I/Q 正負訊號判決法
rx_bits_raw = zeros(length(rx_symbols_sync) * 2, 1);

for k = 1:length(rx_symbols_sync)
    r_real = real(rx_symbols_sync(k));
    r_imag = imag(rx_symbols_sync(k));
    
    if r_real >= 0 && r_imag >= 0  % 第一象限 (45) -> 00
        bits = [0; 0];
    elseif r_real < 0 && r_imag >= 0 % 第二象限 (135) -> 01
        bits = [0; 1];
    elseif r_real < 0 && r_imag < 0  % 第三象限 (225) -> 11
        bits = [1; 1];
    else                             % 第四象限 (315) -> 10
        bits = [1; 0];
    end
    rx_bits_raw(2*k-1 : 2*k) = bits;
end

rx_header = rx_bits_raw(1:HeaderLength_Bits);
rx_payload_scrambled = rx_bits_raw(HeaderLength_Bits+1 : end);

num_err = sum(abs(header_bits - rx_header));
ber = num_err / length(header_bits);
fprintf('Header BER: %.4f (%d bit errors)\n', ber, num_err);

descrambler = comm.Descrambler(2, [1 1 1 0 1], 'InitialConditions', [0 0 0 0]);
rx_payload_descrambled = descrambler(rx_payload_scrambled);

%% 7. 資料解析 (Parsing)
msg_len_bits = 84;             % 這個長度為傳送字元*7
rx_msg_bits = rx_payload_descrambled(1:msg_len_bits);

rx_msg_matrix = reshape(rx_msg_bits, 7, []).';
rx_ascii = rx_msg_matrix * [64 32 16 8 4 2 1]';
rx_str = char(rx_ascii);

fprintf('\n----------------------------------------\n');
fprintf('解碼訊息: "%s"\n', rx_str);
fprintf('----------------------------------------\n');
%% 8. 繪圖 (星座圖對比)
figure('Name', 'QPSK Simulation', 'Color', 'w', 'Position', [100, 100, 950, 450]);

subplot(1,2,1);
plot(real(frame_symbols_raw), imag(frame_symbols_raw), 'r.', 'MarkerSize', 8);
hold on; xline(0, '--k'); yline(0, '--k');
title('1. Before Phase Sync (Raw Symbols)', 'FontSize', 11);
axis square; grid on;

max_val = max(abs([real(frame_symbols_raw); imag(frame_symbols_raw)])) * 1.2;
xlim([-max_val max_val]); ylim([-max_val max_val]);

subplot(1,2,2);
plot(real(rx_symbols_sync), imag(rx_symbols_sync), 'b.', 'MarkerSize', 8);
hold on; xline(0, '--k'); yline(0, '--k');
title('2. After Phase Sync (Demodulation Ready)', 'FontSize', 11);
axis square; grid on;
xlim([-max_val max_val]); ylim([-max_val max_val]);