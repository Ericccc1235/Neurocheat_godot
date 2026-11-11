"""
NeuroCheat 外部生理訊號發送端工具 (External Signal Sender)
用於測試或串接【模式二：外部訊號輸入模式 (EXTERNAL)】！
透過本地 UDP 埠 (127.0.0.1:5005) 即時將外部 ECG (心率 BPM) 與 EEG (腦波專注度 %) 傳入遊戲。

使用方式：
1. 自動連續發送模擬生理訊號：
   python external_signal_sender.py --auto
2. 互動式手動輸入外部訊號：
   python external_signal_sender.py
"""

import socket
import time
import math
import sys

UDP_IP = "127.0.0.1"
UDP_PORT = 5005

def send_signal(sock, ecg, eeg, emg=None):
    if emg is not None:
        msg = f"ECG:{ecg:.1f},EEG:{eeg:.1f},EMG:{int(emg)}"
    else:
        msg = f"ECG:{ecg:.1f},EEG:{eeg:.1f}"
    try:
        sock.sendto(msg.encode("utf-8"), (UDP_IP, UDP_PORT))
    except Exception:
        pass
    try:
        with open("external_signals.json", "w", encoding="utf-8") as f:
            if emg is not None:
                f.write(f'{{"ecg": {ecg:.1f}, "eeg": {eeg:.1f}, "emg": {int(emg)}}}')
            else:
                f.write(f'{{"ecg": {ecg:.1f}, "eeg": {eeg:.1f}}}')
    except Exception:
        pass
    return msg

def run_auto_stream(sock):
    print(f"📡 開始向 NeuroCheat ({UDP_IP}:{UDP_PORT}) 連續發送外部 ECG & EEG 訊號 (按 Ctrl+C 停止)...")
    t0 = time.time()
    try:
        while True:
            elapsed = time.time() - t0
            # 產生隨時間平滑變化的外部心率 (68 ~ 115 BPM) 與腦波專注度 (30% ~ 95%)
            ecg = 82.0 + 25.0 * math.sin(elapsed * 0.4)
            eeg = 68.0 + 28.0 * math.cos(elapsed * 0.3)
            msg = send_signal(sock, ecg, eeg)
            print(f"\r[已傳送外部訊號] {msg}   ", end="", flush=True)
            time.sleep(0.1)
    except KeyboardInterrupt:
        print("\n已停止外部訊號發送。")

def run_interactive(sock):
    print("=" * 60)
    print("🧠 NeuroCheat 外部 ECG / EEG 訊號傳送器 (UDP 127.0.0.1:5005)")
    print("=" * 60)
    print("指令說明：")
    print("  輸入兩個數字 (空白分隔)，例如： 95 85   -> 設定 ECG=95 BPM, EEG=85%")
    print("  輸入 auto                              -> 切換為自動連續波形串流")
    print("  輸入 q                                 -> 離開程式")
    print("-" * 60)

    while True:
        try:
            raw = input("請輸入外部 [ECG心率 EEG專注度] (例如 85 90): ").strip()
        except (EOFError, KeyboardInterrupt):
            break

        if not raw:
            continue
        if raw.lower() in ("q", "quit", "exit"):
            break
        if raw.lower() == "auto":
            run_auto_stream(sock)
            continue

        parts = raw.replace(",", " ").split()
        try:
            if len(parts) >= 2:
                ecg = float(parts[0])
                eeg = float(parts[1])
                emg = float(parts[2]) if len(parts) >= 3 else None
                msg = send_signal(sock, ecg, eeg, emg)
                print(f"✅ 已成功送出外部訊號 -> {msg}")
            else:
                print("⚠️ 格式錯誤！請輸入兩個數值，例如：85 90")
        except ValueError:
            print("⚠️ 數值解析錯誤，請輸入數字！")

if __name__ == "__main__":
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    if "--auto" in sys.argv:
        run_auto_stream(sock)
    else:
        run_interactive(sock)
