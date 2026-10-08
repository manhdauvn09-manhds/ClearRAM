using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
namespace MemoryClear {
  [StructLayout(LayoutKind.Sequential)] public struct MemoryStatus {
    public uint Length, Load; public ulong TotalPhysical, AvailablePhysical, TotalPageFile, AvailablePageFile, TotalVirtual, AvailableVirtual, AvailableExtendedVirtual;
  }
  [StructLayout(LayoutKind.Sequential)] public struct PerformanceInfo {
    public uint Size; public UIntPtr CommitTotal, CommitLimit, CommitPeak, PhysicalTotal, PhysicalAvailable, SystemCache, KernelTotal, KernelPaged, KernelNonpaged, PageSize;
    public uint HandleCount, ProcessCount, ThreadCount;
  }
  public sealed class SystemMetrics {
    public ulong TotalBytes, AvailableBytes, CommitBytes, CommitLimitBytes;
    public long Idle, Kernel, User, Timestamp;
  }
  public sealed class Identity {
    public int Pid, Session; public long StartTicks; public string Path, Sid;
    public bool Critical, Known; public string Error;
  }
  public sealed class ProcessRow {
    public int Pid {get;set;}
    public string Name {get;set;}
    public long StartTicks {get;set;}
    public string Path {get;set;}
    public double? RamMB {get;set;}
    public double? PrivateMB {get;set;}
    public double? Cpu {get;set;}
    public string Policy {get;set;}
    public bool Allowed {get;set;}
    public bool AllowClose {get;set;}
    public Identity Identity {get;set;}
  }
  public static class Native {
    [DllImport("psapi.dll", SetLastError=true)] internal static extern bool EmptyWorkingSet(IntPtr process);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GlobalMemoryStatusEx(ref MemoryStatus data);
    [DllImport("psapi.dll", SetLastError=true)] static extern bool GetPerformanceInfo(ref PerformanceInfo data, uint size);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessTimes(IntPtr process, out long creation, out long exit, out long kernel, out long user);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool IsProcessCritical(IntPtr process, out bool critical);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder path, ref int length);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ProcessIdToSessionId(int pid, out int session);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool GetTokenInformation(IntPtr token, int informationClass, IntPtr info, int size, out int needed);
    [DllImport("kernel32.dll", SetLastError=true)] internal static extern uint WaitForSingleObject(IntPtr handle, uint ms);
    [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool TerminateProcess(IntPtr handle, uint exitCode);
    [DllImport("user32.dll", SetLastError=true)] static extern uint GetWindowThreadProcessId(IntPtr window, out int pid);
    [DllImport("user32.dll", SetLastError=true)] static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    static string Owner(IntPtr process) {
      IntPtr token; if(!OpenProcessToken(process, 8, out token)) throw new Win32Exception();
      try { int needed; GetTokenInformation(token, 1, IntPtr.Zero, 0, out needed); if(needed <= 0) throw new Win32Exception();
        IntPtr info=Marshal.AllocHGlobal(needed); try { if(!GetTokenInformation(token,1,info,needed,out needed)) throw new Win32Exception(); return new SecurityIdentifier(Marshal.ReadIntPtr(info)).Value; } finally { Marshal.FreeHGlobal(info); }
      } finally { CloseHandle(token); }
    }
    internal static Identity ReadIdentity(IntPtr handle, int pid) {
      var result=new Identity {Pid=pid}; long created, exit, kernel, user; bool critical; int session;
      if(!GetProcessTimes(handle,out created,out exit,out kernel,out user)) throw new Win32Exception();
      if(!IsProcessCritical(handle,out critical)) throw new Win32Exception();
      int length=32768; var path=new StringBuilder(length); if(!QueryFullProcessImageName(handle,0,path,ref length)) throw new Win32Exception();
      if(!ProcessIdToSessionId(pid,out session)) throw new Win32Exception();
      result.StartTicks=DateTime.FromFileTimeUtc(created).Ticks; result.Path=path.ToString(); result.Critical=critical; result.Session=session; result.Sid=Owner(handle); result.Known=true; return result;
    }
    public static Identity Inspect(int pid) {
      IntPtr handle=OpenProcess(0x1000,false,pid); if(handle==IntPtr.Zero) return new Identity {Pid=pid,Error=new Win32Exception().Message};
      try { return ReadIdentity(handle,pid); } catch(Exception error) { return new Identity {Pid=pid,Error=error.Message}; } finally { CloseHandle(handle); }
    }
    public static GuardedProcess Acquire(int pid, long expectedTicks, bool terminate) {
      IntPtr handle=OpenProcess(0x1000 | 0x100000 | (terminate ? 1u : 0u),false,pid); if(handle==IntPtr.Zero) throw new Win32Exception();
      try { Identity identity=ReadIdentity(handle,pid); if(identity.StartTicks!=expectedTicks || WaitForSingleObject(handle,0)!=258) throw new InvalidOperationException("Process identity changed or process exited."); return new GuardedProcess(handle,identity,terminate); } catch { CloseHandle(handle); throw; }
    }
    public static int ForegroundProcessId() { int pid; return GetWindowThreadProcessId(GetForegroundWindow(),out pid)==0 ? 0 : pid; }
    public static GuardedProcess AcquireForTrim(int pid,long expectedTicks) {
      IntPtr handle=OpenProcess(0x1000 | 0x100000 | 0x100,false,pid); if(handle==IntPtr.Zero) throw new Win32Exception();
      try { var identity=ReadIdentity(handle,pid); if(identity.StartTicks!=expectedTicks || WaitForSingleObject(handle,0)!=258) throw new InvalidOperationException("Process changed or exited."); return new GuardedProcess(handle,identity,false,true); } catch { CloseHandle(handle);throw; }
    }
    internal static double ReadCpuSeconds(IntPtr handle) { long creation,exit,kernel,user; if(!GetProcessTimes(handle,out creation,out exit,out kernel,out user)) throw new Win32Exception(); return (kernel+user)/10000000.0; }
    public static SystemMetrics ReadSystem() {
      var memory=new MemoryStatus(); memory.Length=(uint)Marshal.SizeOf(typeof(MemoryStatus)); if(!GlobalMemoryStatusEx(ref memory)) throw new Win32Exception();
      var perf=new PerformanceInfo(); perf.Size=(uint)Marshal.SizeOf(typeof(PerformanceInfo)); if(!GetPerformanceInfo(ref perf,perf.Size)) throw new Win32Exception();
      long idle,kernel,user; if(!GetSystemTimes(out idle,out kernel,out user)) throw new Win32Exception();
      return new SystemMetrics {TotalBytes=memory.TotalPhysical,AvailableBytes=memory.AvailablePhysical,CommitBytes=perf.CommitTotal.ToUInt64()*perf.PageSize.ToUInt64(),CommitLimitBytes=perf.CommitLimit.ToUInt64()*perf.PageSize.ToUInt64(),Idle=idle,Kernel=kernel,User=user,Timestamp=Stopwatch.GetTimestamp()};
    }
    internal static bool RequestClose(Identity identity) {
      using(var process=Process.GetProcessById(identity.Pid)) {
        if(process.StartTime.ToUniversalTime().Ticks!=identity.StartTicks) throw new InvalidOperationException("Process identity changed.");
        IntPtr window=process.MainWindowHandle; int owner;
        if(window==IntPtr.Zero || GetWindowThreadProcessId(window,out owner)==0 || owner!=identity.Pid) return false;
        return PostMessage(window,0x10,IntPtr.Zero,IntPtr.Zero);
      }
    }
  }
  public sealed class GuardedProcess : IDisposable {
    IntPtr handle; readonly bool canTerminate,canTrim; public Identity Identity {get; private set;}
    internal GuardedProcess(IntPtr handle,Identity identity,bool terminate,bool trim=false) {this.handle=handle;Identity=identity;canTerminate=terminate;canTrim=trim;}
    public double CpuSeconds {get{return Native.ReadCpuSeconds(handle);}}
    public void Trim() {if(!canTrim || handle==IntPtr.Zero || HasExited) throw new InvalidOperationException("No trim capability or process exited.");if(!Native.EmptyWorkingSet(handle)) throw new Win32Exception();}
    public bool HasExited {get {return Native.WaitForSingleObject(handle,0)==0;}}
    public bool CloseWindow() { if(canTrim) throw new InvalidOperationException("Trim handle cannot close a process."); if(handle==IntPtr.Zero || HasExited) throw new InvalidOperationException("Process exited."); return Native.RequestClose(Identity); }
    public void Kill() { if(!canTerminate || handle==IntPtr.Zero) throw new InvalidOperationException("No termination capability."); if(!Native.TerminateProcess(handle,1)) throw new Win32Exception(); }
    public bool Wait(int milliseconds) {return Native.WaitForSingleObject(handle,(uint)milliseconds)==0;}
    public void Dispose() {if(handle!=IntPtr.Zero){Native.CloseHandle(handle);handle=IntPtr.Zero;}}
  }
}
