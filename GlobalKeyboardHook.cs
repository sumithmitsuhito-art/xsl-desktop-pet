using Godot;
using System;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Threading;

namespace XiaoSongLv
{
    /// <summary>
    /// 全局键盘监听节点（Godot C# 版）。
    /// 后台线程用 Windows 低级全局钩子（WH_KEYBOARD_LL）监听任意窗口的按键；
    /// 按键事件放入线程安全队列，Godot 主线程每帧在 _Process 里取出，通过信号 KeyPressed 发给 GDScript。
    /// 用法（GDScript）：connect 到 KeyPressed，或监听本节点的信号。
    /// </summary>
    [GlobalClass]
    public partial class GlobalKeyboardHook : Node
    {
        // 发给 GDScript 的信号：keyCode=虚拟键码，isDown=true按下/false抬起
        [Signal] public delegate void KeyPressedEventHandler(int keyCode, bool isDown);

        // Windows API 声明
        private const int WH_KEYBOARD_LL = 13;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_KEYUP = 0x0101;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const int WM_SYSKEYUP = 0x0105;

        private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr GetModuleHandle(string lpModuleName);

        [DllImport("user32.dll")]
        private static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

        [DllImport("user32.dll")]
        private static extern bool TranslateMessage(ref MSG lpMsg);

        [DllImport("user32.dll")]
        private static extern IntPtr DispatchMessage(ref MSG lpMsg);

        [StructLayout(LayoutKind.Sequential)]
        private struct MSG
        {
            public IntPtr hwnd;
            public uint message;
            public IntPtr wParam;
            public IntPtr lParam;
            public uint time;
            public int pt_x;
            public int pt_y;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct KBDLLHOOKSTRUCT
        {
            public uint vkCode;
            public uint scanCode;
            public uint flags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        // 钩子线程引用（实例字段，防止被 GC 回收）
        private Thread _hookThread;
        private bool _running = false;
        private IntPtr _hookId = IntPtr.Zero;
        private LowLevelKeyboardProc _proc; // 保持引用，防止委托被 GC 回收

        // 线程安全队列：钩子线程写入，主线程 _Process 读取
        private readonly ConcurrentQueue<(int keyCode, bool isDown)> _queue = new();

        public override void _Ready()
        {
            _proc = HookCallback;
            _running = true;
            _hookThread = new Thread(ThreadMain) { IsBackground = true };
            _hookThread.Start();
            GD.Print("[C#] GlobalKeyboardHook 已启动，正在监听全局键盘...");
        }

        // 后台线程入口：装钩子 + 跑消息循环
        private void ThreadMain()
        {
            _hookId = SetHook();
            if (_hookId == IntPtr.Zero)
            {
                GD.PrintErr("[C#] 全局键盘钩子安装失败（可能需管理员权限或非 Windows 平台）");
                _running = false;
                return;
            }
            GD.Print("[C#] 钩子已安装，开始监听...");

            MSG msg;
            while (_running && GetMessage(out msg, IntPtr.Zero, 0, 0) != 0)
            {
                TranslateMessage(ref msg);
                DispatchMessage(ref msg);
            }

            UnhookWindowsHookEx(_hookId);
            _hookId = IntPtr.Zero;
        }

        private IntPtr SetHook()
        {
            IntPtr mod = GetModuleHandle(null);
            return SetWindowsHookEx(WH_KEYBOARD_LL, _proc, mod, 0);
        }

        // 钩子回调（在后台线程被调用）：只把按键塞进队列，不碰 Godot 节点
        private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            try
            {
                if (nCode >= 0)
                {
                    uint msg = (uint)wParam;
                    bool isDown = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
                    bool isUp = msg == WM_KEYUP || msg == WM_SYSKEYUP;
                    if (isDown || isUp)
                    {
                        KBDLLHOOKSTRUCT data = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
                        _queue.Enqueue(((int)data.vkCode, isDown));
                    }
                }
            }
            catch (Exception e)
            {
                GD.PrintErr("[C#] 钩子回调异常: " + e.Message);
            }
            return CallNextHookEx(_hookId, nCode, wParam, lParam);
        }

        // 主线程每帧：从队列取出按键，通过信号发给 GDScript（必须在主线程发信号）
        public override void _Process(double delta)
        {
            while (_queue.TryDequeue(out var item))
            {
                EmitSignal(SignalName.KeyPressed, item.keyCode, item.isDown);
            }
        }

        public override void _ExitTree()
        {
            _running = false;
            // 若钩子线程在 GetMessage 里阻塞，需要唤醒它退出；这里用 PostThreadMessage 或直接靠 _running + 线程退出。
            // 简单起见：钩子线程设为后台线程，退出时随进程结束即可；显式卸载钩子。
            if (_hookId != IntPtr.Zero)
            {
                UnhookWindowsHookEx(_hookId);
                _hookId = IntPtr.Zero;
            }
        }
    }
}
