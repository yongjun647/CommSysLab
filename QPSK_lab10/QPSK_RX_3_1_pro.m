%% QPSK Receiver for SDR (基於 Lab8 模擬邏輯修復版)
clc; clear; close all;

%% 1. 參數設定 (System Parameters)
SR = 122.88e6;                  % 取樣率
Upsampling_Factor = 64;         % 每個 Symbol 的取樣點數
Rolloff = 0.5;
FilterSpan = 64;
CenterFreq = 433;               % MHz
RxGain = -20;
RxTime = 0.008;                 % 錄取時間 8ms

HeaderLength_Bits = 26;         % 固定的 Header 長度
LengthField_Bits = 8;           % 固定的長度指示器位元數

% 產生本地端的 Header 參考符號 (用於同步與相位校正)
barker_13 = [1 1 1 1 1 0 0 1 1 0 1 0 1]';
header_bits = [barker_13; barker_13];
constellation_lut = [exp(1j*pi/4); exp(1j*3*pi/4); exp(1j*7*pi/4); exp(1j*5*pi/4)];

% 將 Header 轉為 Symbols (對應發射端的 Gray Mapping)
header_sym_idx = header_bits(1:2:end)*2 + header_bits(2:2:end);
header_symbols = constellation_lut(header_sym_idx + 1);

%% 2. SDR 硬體接收 (Hardware Reception)
fprintf('\n--- 開始設定 SDR RX ---\n');
try
    LO_CHANGE(0, CenterFreq, CenterFreq);
    set_RX_Ref_Level_ELSDR([0 RxGain]);
    RxLen = round(RxTime * SR);
    
    rx_data_raw = RX(1, RxLen);
    if size(rx_data_raw, 1) == 2
        rx_signal = rx_data_raw(1,:) + 1j*rx_data_raw(2,:);
    else
        rx_signal = rx_data_raw;
    end
    rx_signal = double(rx_signal(:));
    rx_signal = rx_signal - mean(rx_signal);
catch
    warning('SDR 連接失敗，使用模擬雜訊測試...');
    RxLen = round(RxTime * SR);
    rx_signal = (randn(RxLen, 1) + 1j*randn(RxLen, 1)) * 0.1; 
end

%% 3. 脈衝整形濾波 (RRC Matched Filter)
rrc_filter = rcosdesign(Rolloff, FilterSpan, Upsampling_Factor, 'sqrt');
rx_filtered = conv(rx_signal, rrc_filter, 'same');

%% 4. Frame 同步 (基於 Lab8 的 Normalized Timing Metric)
% 產生本地端 Header 波形供 Matched Filter 使用
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
% 計算同步指標
timing_metric = (abs(rx_corr).^2) ./ (rx_energy_moving * header_energy_const + 1e-10);
[max_metric, peak_idx] = max(timing_metric);

Sync_Threshold = 0.4;
fprintf('-> [時間同步] 最大指標 (Metric): %.4f\n', max_metric);
if max_metric < Sync_Threshold
    warning('同步指標過低，可能是純雜訊或未收到有效封包。');
end

% 計算 Frame 起點
start_idx = peak_idx - L_header + 1;
if start_idx < 1, start_idx = 1; end

% 拓寬管路：預抓 2000 個 symbols 的暫時大區塊，從中動態解析長度
max_look_symbols = 2000;
samples_to_extract = max_look_symbols * Upsampling_Factor;
if start_idx + samples_to_extract - 1 > length(rx_filtered)
    samples_to_extract = length(rx_filtered) - start_idx + 1;
end
frame_signal_oversampled = rx_filtered(start_idx : start_idx + samples_to_extract - 1);

%% 5. 下取樣與純靜態相位校正
frame_symbols_raw = frame_signal_oversampled(1 : Upsampling_Factor : end);

rx_header_syms = frame_symbols_raw(1 : length(header_symbols));
phase_diff_vec = angle(rx_header_syms .* conj(header_symbols));
estimated_phase_error = mean(phase_diff_vec);

fprintf('-> [相位同步] 偵測到靜態相位偏移: %.2f 度\n', estimated_phase_error * 180/pi);
rx_symbols_sync = frame_symbols_raw * exp(-1j * estimated_phase_error);

%% 6. 解調第一階段：I/Q 正負訊號判決法 (基於 Lab8)
rx_bits_raw = zeros(length(rx_symbols_sync) * 2, 1);

for k = 1:length(rx_symbols_sync)
    r_real = real(rx_symbols_sync(k));
    r_imag = imag(rx_symbols_sync(k));
    
    if r_real >= 0 && r_imag >= 0      % 第一象限 (45) -> 00
        bits = [0; 0];
    elseif r_real < 0 && r_imag >= 0   % 第二象限 (135) -> 01
        bits = [0; 1];
    elseif r_real < 0 && r_imag < 0    % 第三象限 (225) -> 11
        bits = [1; 1];
    else                               % 第四象限 (315) -> 10
        bits = [1; 0];
    end
    rx_bits_raw(2*k-1 : 2*k) = bits;
end

%% 7. 解調第二階段：動態裁切與解析字串 (基於 PPT 架構)
% A. 讀取 8-bit 長度欄位 (Decode Length Field)
len_start_bit = HeaderLength_Bits + 1;
len_end_bit = HeaderLength_Bits + LengthField_Bits;
length_bits_rx = rx_bits_raw(len_start_bit:len_end_bit);
payload_char_len = bi2de(length_bits_rx.', 'left-msb');

% B. 根據解出的長度裁切
total_payload_bits = payload_char_len * 7;
total_bits = HeaderLength_Bits + LengthField_Bits + total_payload_bits;
if mod(total_bits, 2) ~= 0
    total_bits = total_bits + 1; % 考慮 Dummy bit
end
total_frame_symbols = total_bits / 2;
rx_symbols_final = rx_symbols_sync(1:total_frame_symbols); 

% C. 取出 Payload 並解擾碼
payload_start_bit = len_end_bit + 1;
payload_end_bit = len_end_bit + total_payload_bits;
payload_scrambled_rx = rx_bits_raw(payload_start_bit:payload_end_bit);

descrambler = comm.Descrambler(2, [1 1 1 0 1], 'InitialConditions', [0 0 0 0]);
payload_raw_rx = descrambler(payload_scrambled_rx);

% D. 解析字串
payload_matrix = reshape(payload_raw_rx, 7, []).';
msg_ascii_rx = bi2de(payload_matrix, 'left-msb');
rx_str = char(msg_ascii_rx.');

%% 8. 輸出結果與繪圖
fprintf('\n---------------------------------------\n');
fprintf('成功讀取: %d 個字元\n', payload_char_len);
fprintf('封包總長度為 %d bits (%d symbols)\n', total_bits, total_frame_symbols);
fprintf('---------------------------------------\n');
fprintf(' 【解碼成功】 訊息內容:\n');
fprintf('"%s"\n', rx_str);
fprintf('---------------------------------------\n');

figure('Name', 'SDR Constellation', 'Color', 'w', 'Position', [100, 150, 900, 450]);
max_val = max(abs([real(rx_symbols_final); imag(rx_symbols_final)])) * 1.6;

% 圖 1：完全未校正的原始 Symbols
subplot(1,2,1);
plot(real(frame_symbols_raw(1:total_frame_symbols)), imag(frame_symbols_raw(1:total_frame_symbols)), 'r.', 'MarkerSize', 8);
hold on; xline(0, '--k'); yline(0, '--k');
title('1. Before Phase Sync (Raw)', 'FontSize', 12);
axis square; grid on; xlim([-max_val max_val]); ylim([-max_val max_val]);

% 圖 2：相位同步後的 Symbols
subplot(1,2,2);
plot(real(rx_symbols_final), imag(rx_symbols_final), 'b.', 'MarkerSize', 8)
hold on; xline(0, '--k'); yline(0, '--k');
title(['2. After Static Sync (Symbols: ', num2str(total_frame_symbols), ')'], 'FontSize', 12);
axis square; grid on; xlim([-max_val max_val]); ylim([-max_val max_val]);