using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Security.Cryptography;
using Microsoft.Win32.SafeHandles;

namespace MemoryClear.Storage {
 // Process-local coordinator state shared by GUI and worker runspaces. Not a privileged trust boundary.
 public static class OperationSessionStore {
  public static readonly System.Collections.Concurrent.ConcurrentDictionary<string,object> TempSessions=new System.Collections.Concurrent.ConcurrentDictionary<string,object>();
  public static readonly System.Collections.Concurrent.ConcurrentDictionary<string,object> Sessions=new System.Collections.Concurrent.ConcurrentDictionary<string,object>();
  public static void Remove(string id){object unused;Sessions.TryRemove(id,out unused);}
 }
 public sealed class FileRecord {
  public string Path {get;set;} public string Root {get;set;} public string Identity {get;set;} public string AncestorIdentity {get;set;}
  public long LogicalBytes {get;set;} public long AllocatedBytes {get;set;} public long LastWriteFileTime {get;set;}
  public uint Links {get;set;} public uint Attributes {get;set;}
 }
 public sealed class ScanResult {
  public List<FileRecord> Files=new List<FileRecord>(); public List<string> Issues=new List<string>();
  public int Visited,Skipped,Duplicates; public bool Truncated,Cancelled;
  public int Matched,Offset; public bool HasMore;
  public long LogicalBytes,AllocatedBytes; public double Seconds;
 }
 public sealed class FixtureReceipt {
  public string BackupPath,BackupIdentity,BackupAncestorIdentity,Sha256,CleanupWarning; public long Bytes;
  public bool Deleted;
 }
 public sealed class DirectoryProbe {
  public string Path,State,Identity,AncestorIdentity,Issue;
 }
 public static class FileInventory {
  [StructLayout(LayoutKind.Sequential)] struct Info {public uint Attr;public System.Runtime.InteropServices.ComTypes.FILETIME Created,Accessed,Written;public uint Volume,SizeHigh,SizeLow,Links,IndexHigh,IndexLow;}
  [StructLayout(LayoutKind.Sequential)] struct Standard {public long Allocation,End;public uint Links;public byte Pending,Directory;}
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info info);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandleEx(SafeFileHandle h,int kind,out Standard info,uint size);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(SafeFileHandle h,StringBuilder path,uint size,uint flags);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFileAttributes(string path);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetFileInformationByHandle(SafeFileHandle h,int kind,ref Disposition disposition,uint size);
  [DllImport("kernel32.dll",SetLastError=true,EntryPoint="SetFileInformationByHandle")] static extern bool SetFileInformationBuffer(SafeFileHandle h,int kind,IntPtr buffer,uint size);
  [StructLayout(LayoutKind.Sequential)] struct Disposition {[MarshalAs(UnmanagedType.Bool)]public bool Delete;}
  const uint UnsafeAttributes=0x400|0x1000|0x40000|0x400000; // reparse, offline, recall-on-open/access
  public static string Canonical(string path) {
   if(String.IsNullOrWhiteSpace(path)||path.StartsWith(@"\\")||path.IndexOf(':',2)>=0)throw new ArgumentException("Only local drive paths without alternate streams are allowed.");
   string full=System.IO.Path.GetFullPath(path);
   if(full.Length<3||full[1]!=':'||full[2]!='\\')throw new ArgumentException("Absolute local path required.");
   if(full.TrimEnd('\\').Length==2)throw new ArgumentException("Drive-wide discovery is not an allowed scan root.");
   return full.TrimEnd('\\');
  }
  public static bool Within(string path,string root){return Canonical(path).StartsWith(Canonical(root)+@"\",StringComparison.OrdinalIgnoreCase);}
  static string Extended(string path){return @"\\?\"+path;}
  static Info Read(SafeFileHandle h){Info i;if(!GetFileInformationByHandle(h,out i))throw new Win32Exception();if((i.Attr&UnsafeAttributes)!=0)throw new IOException("Reparse/offline/cloud entry blocked.");return i;}
  static string Key(Info i){return i.Volume.ToString("X8")+":"+i.IndexHigh.ToString("X8")+i.IndexLow.ToString("X8");}
  static void ExactPath(SafeFileHandle h,string expected){var sb=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(h,sb,(uint)sb.Capacity,0);if(n==0||n>=sb.Capacity)throw new Win32Exception();string actual=sb.ToString();if(actual.StartsWith(@"\\?\"))actual=actual.Substring(4);if(!String.Equals(actual.TrimEnd('\\'),expected,StringComparison.OrdinalIgnoreCase))throw new IOException("Resolved path changed or aliased.");}
  sealed class DirectoryLease : IDisposable {
   readonly List<SafeFileHandle> handles=new List<SafeFileHandle>();public string RootIdentity;public string AncestorIdentity;
   public DirectoryLease(string directory,string root){try{
    string drive=System.IO.Path.GetPathRoot(directory),current=drive.TrimEnd('\\');
    var chain=new List<string>();chain.Add(drive);foreach(string part in directory.Substring(drive.Length).Split(new[]{'\\'},StringSplitOptions.RemoveEmptyEntries)){current=current+@"\"+part;chain.Add(current);}
    if(chain.Count>65)throw new IOException("Path depth limit.");
    var keys=new List<string>();foreach(string entry in chain){uint attr=GetFileAttributes(Extended(entry));if(attr==UInt32.MaxValue)throw new Win32Exception();if((attr&UnsafeAttributes)!=0)throw new IOException("Protected ancestor.");
     // No FILE_SHARE_DELETE: a held ancestor cannot be renamed/replaced while enumerating.
     SafeFileHandle h=CreateFile(Extended(entry),0x80,3,IntPtr.Zero,3,0x02000000|0x00200000,IntPtr.Zero);
     if(h.IsInvalid){h.Dispose();throw new Win32Exception();}handles.Add(h);Info i=Read(h);if((i.Attr&0x10)==0)throw new IOException("Ancestor is not a directory.");
     keys.Add(Key(i));ExactPath(h,entry.TrimEnd('\\'));if(String.Equals(entry.TrimEnd('\\'),root,StringComparison.OrdinalIgnoreCase))RootIdentity=Key(i);
    }
    if(RootIdentity==null)throw new IOException("Directory outside root.");AncestorIdentity=String.Join("/",keys.ToArray());
   }catch{Dispose();throw;}}
   public void Dispose(){for(int i=handles.Count-1;i>=0;i--)handles[i].Dispose();handles.Clear();}
  }
  public static FileRecord Snapshot(string file,string root){file=Canonical(file);root=Canonical(root);if(!Within(file,root))throw new IOException("Outside scan root.");using(var lease=new DirectoryLease(System.IO.Path.GetDirectoryName(file),root)){var item=SnapshotHeld(file,root);item.AncestorIdentity=lease.AncestorIdentity;return item;}}
  // Readonly observation, not a promise that a directory remains empty after return.
  public static DirectoryProbe ProbeFilePresence(string file,string root){
   var result=new DirectoryProbe{Path=Canonical(file),State="Unavailable"};root=Canonical(root);
   if(!Within(result.Path,root))throw new IOException("Outside presence root.");
   try{using(var lease=new DirectoryLease(System.IO.Path.GetDirectoryName(result.Path),root)){
    uint attributes=GetFileAttributes(Extended(result.Path));
    if(attributes==UInt32.MaxValue){int error=Marshal.GetLastWin32Error();if(error==2||error==3)result.State="Absent";else result.Issue="Win32:"+error;}
    else result.State=(attributes&UnsafeAttributes)!=0?"Protected":"Present";
    result.AncestorIdentity=lease.AncestorIdentity;
   }}catch(Exception e){result.Issue=e.GetType().Name+":"+e.HResult.ToString("X8");}
   return result;
  }
  public static DirectoryProbe ProbeDirectory(string path){
   var result=new DirectoryProbe{Path=Canonical(path),State="Unavailable"};
   try{using(var lease=new DirectoryLease(result.Path,result.Path)){
    using(var iterator=Directory.EnumerateFileSystemEntries(result.Path).GetEnumerator()){
     result.State=iterator.MoveNext()?"Present":"EmptyAtObservation";
     result.Identity=lease.RootIdentity;result.AncestorIdentity=lease.AncestorIdentity;
    }
   }}catch(Win32Exception e){if(e.NativeErrorCode==2||e.NativeErrorCode==3)result.State="Absent";else result.Issue="Win32:"+e.NativeErrorCode;}
   catch(Exception e){result.Issue=e.GetType().Name+":"+e.HResult.ToString("X8");}
   return result;
  }
  // Only the app's own bounded metadata file; caller holds this lease across read/validate/update.
  // Not an atomic transaction: interrupted writes are rejected by the caller's JSON/checksum validation.
  public sealed class ObservationStore : IDisposable {
   DirectoryLease lease; FileStream stream; readonly int maximumBytes;
   public ObservationStore(string projectRoot,int limit){
    if(limit<4096||limit>1048576)throw new ArgumentException("Invalid history size budget.");
    maximumBytes=limit;projectRoot=Canonical(projectRoot);string directory=System.IO.Path.Combine(projectRoot,".data");
    SafeFileHandle handle=null;
    try{
     using(var parent=new DirectoryLease(projectRoot,projectRoot)){
      Directory.CreateDirectory(directory);lease=new DirectoryLease(directory,directory);
     }
     string path=System.IO.Path.Combine(directory,"disk-owner-history.json");
     handle=CreateFile(Extended(path),0xC0000000,0,IntPtr.Zero,4,0x00200000,IntPtr.Zero);
     if(handle.IsInvalid)throw new Win32Exception();
     Info info=Read(handle);ExactPath(handle,path);Standard standard;
     if(!GetFileInformationByHandleEx(handle,1,out standard,(uint)Marshal.SizeOf(typeof(Standard))))throw new Win32Exception();
     if(info.Links!=1||standard.Directory!=0||standard.Pending!=0||standard.End>maximumBytes)throw new IOException("Unsafe or oversized history store.");
     stream=new FileStream(handle,FileAccess.ReadWrite,4096,false);handle=null;
    }catch{if(handle!=null)handle.Dispose();Dispose();throw;}
   }
   public string ReadText(){
    if(stream.Length>maximumBytes)throw new IOException("History exceeds budget.");
    stream.Position=0;var bytes=new byte[(int)stream.Length];int used=0,count;
    while(used<bytes.Length&&(count=stream.Read(bytes,used,bytes.Length-used))>0)used+=count;
    if(used!=bytes.Length)throw new IOException("Incomplete history read.");
    return new UTF8Encoding(false,true).GetString(bytes);
   }
   public void Commit(string text){
    byte[] bytes=new UTF8Encoding(false,true).GetBytes(text);
    if(bytes.Length==0||bytes.Length>maximumBytes)throw new IOException("History exceeds budget.");
    stream.Position=0;stream.Write(bytes,0,bytes.Length);stream.SetLength(bytes.Length);stream.Flush(true);
   }
   public void Dispose(){if(stream!=null){stream.Dispose();stream=null;}if(lease!=null){lease.Dispose();lease=null;}}
  }
  public static ObservationStore OpenObservationStore(string projectRoot,int maximumBytes){return new ObservationStore(projectRoot,maximumBytes);}
  // Fixture-only destructive guard. Production cleanup remains disabled in policy/UI.
  public static void DeleteFixture(FileRecord expected,string artifactRoot){
   string root=Canonical(expected.Root),file=Canonical(expected.Path),artifacts=Canonical(artifactRoot);
   if(!Within(root,artifacts)||!Within(file,root)||!System.IO.Path.GetFileName(root).StartsWith("disk-fixture-",StringComparison.Ordinal)||!File.Exists(System.IO.Path.Combine(root,".memoryclear-fixture")))throw new IOException("Only marked disposable disk-fixture roots are accepted.");
   if(System.IO.Path.GetFileName(file)==".memoryclear-fixture")throw new IOException("Fixture marker is protected.");
   using(var lease=new DirectoryLease(System.IO.Path.GetDirectoryName(file),root)){
    if(expected.AncestorIdentity!=lease.AncestorIdentity)throw new IOException("Ancestor identity changed.");
    // Exclusive open refuses active readers/writers; held ancestors block junction/path replacement.
    using(SafeFileHandle h=CreateFile(Extended(file),0x10000|0x80,0,IntPtr.Zero,3,0x00200000,IntPtr.Zero)){
     if(h.IsInvalid)throw new Win32Exception();Info i=Read(h);ExactPath(h,file);Standard st;if(!GetFileInformationByHandleEx(h,1,out st,(uint)Marshal.SizeOf(typeof(Standard))))throw new Win32Exception();
     long written=((long)i.Written.dwHighDateTime<<32)|(uint)i.Written.dwLowDateTime;
     if((i.Attr&0x10)!=0||i.Links!=1||st.Pending!=0||Key(i)!=expected.Identity||written!=expected.LastWriteFileTime||st.End!=expected.LogicalBytes||st.Allocation!=expected.AllocatedBytes)throw new IOException("File changed, linked or unsafe; refusing delete.");
     var disposition=new Disposition{Delete=true};if(!SetFileInformationByHandle(h,4,ref disposition,(uint)Marshal.SizeOf(typeof(Disposition))))throw new Win32Exception();
    }
   }
  }
  // Development-only transaction. No path in the user profile is accepted here.
  // The observer must durably log each pre-commit stage; an observer failure aborts deletion.
  public static FixtureReceipt ExecuteFixture(FileRecord expected,string artifactRoot,string backupPath,string backupAncestorIdentity,CancellationToken token,Action<string,FixtureReceipt> observer){
   return ExecuteFixtureHeld(expected,artifactRoot,backupPath,backupAncestorIdentity,token,observer,null);
  }
  public static FixtureReceipt ExecuteFixtureWithHash(FileRecord expected,string artifactRoot,string backupPath,string backupAncestorIdentity,CancellationToken token,Action<string,FixtureReceipt> observer,string contentHash){
   if(String.IsNullOrEmpty(contentHash)||contentHash.Length!=64)throw new IOException("Frozen content hash required.");
   return ExecuteFixtureHeld(expected,artifactRoot,backupPath,backupAncestorIdentity,token,observer,contentHash);
  }
  static FixtureReceipt ExecuteFixtureHeld(FileRecord expected,string artifactRoot,string backupPath,string backupAncestorIdentity,CancellationToken token,Action<string,FixtureReceipt> observer,string contentHash){
   string root=Canonical(expected.Root),file=Canonical(expected.Path),artifacts=Canonical(artifactRoot);
   if(!Within(root,artifacts)||!Within(file,root)||!System.IO.Path.GetFileName(root).StartsWith("disk-fixture-",StringComparison.Ordinal)||!File.Exists(System.IO.Path.Combine(root,".memoryclear-fixture")))throw new IOException("Only marked disposable fixture roots are accepted.");
   string name=System.IO.Path.GetFileName(file);
   if(name==".memoryclear-fixture"||name.StartsWith("journal-",StringComparison.OrdinalIgnoreCase))throw new IOException("Fixture evidence is protected.");
   if(observer==null)throw new ArgumentNullException("observer");
   var receipt=new FixtureReceipt();DirectoryLease destinationLease=null;SafeFileHandle destinationHandle=null;FileStream destination=null;
   token.ThrowIfCancellationRequested();try{
   using(var lease=new DirectoryLease(System.IO.Path.GetDirectoryName(file),root)){
    if(expected.AncestorIdentity!=lease.AncestorIdentity)throw new IOException("Ancestor identity changed.");
    using(SafeFileHandle sourceHandle=CreateFile(Extended(file),0x80000000|0x10000|0x80,0,IntPtr.Zero,3,0x00200000,IntPtr.Zero)){
     if(sourceHandle.IsInvalid)throw new Win32Exception();ValidateExpected(sourceHandle,expected);
     using(var source=new FileStream(sourceHandle,FileAccess.Read,65536,false)){
      if(contentHash!=null){if(HashStream(source,token)!=contentHash)throw new IOException("Content changed after approval.");source.Position=0;}
      observer("SourceLocked",receipt);token.ThrowIfCancellationRequested();
      if(!String.IsNullOrEmpty(backupPath)){
       backupPath=Canonical(backupPath);string backupRoot=System.IO.Path.GetDirectoryName(backupPath);
       if(!Within(backupRoot,artifacts)||!System.IO.Path.GetFileName(backupRoot).StartsWith("disk-backup-fixture-",StringComparison.Ordinal)||!File.Exists(System.IO.Path.Combine(backupRoot,".memoryclear-fixture"))||Within(backupPath,root))throw new IOException("Marked separate fixture backup directory required.");
       if(System.IO.Path.GetFileName(backupPath)==".memoryclear-fixture")throw new IOException("Backup marker is protected.");
       destinationLease=new DirectoryLease(backupRoot,backupRoot);
        if(String.IsNullOrEmpty(backupAncestorIdentity)||backupAncestorIdentity!=destinationLease.AncestorIdentity)throw new IOException("Backup ancestor identity changed.");
        // CREATE_NEW never overwrites an existing backup, hardlink or leaf reparse point.
        destinationHandle=CreateFile(Extended(backupPath),0x80000000|0x40000000|0x80,0,IntPtr.Zero,1,0x00200000|0x80000000,IntPtr.Zero);
         if(destinationHandle.IsInvalid)throw new Win32Exception();ExactPath(destinationHandle,backupPath);
         destination=new FileStream(destinationHandle,FileAccess.ReadWrite,65536,false);
          byte[] buffer=new byte[65536];int count;long copied=0;
          while((count=source.Read(buffer,0,buffer.Length))>0){token.ThrowIfCancellationRequested();destination.Write(buffer,0,count);copied+=count;}
          destination.Flush(true);observer("BackupFlushed",receipt);token.ThrowIfCancellationRequested();
          if(copied!=expected.LogicalBytes||destination.Length!=expected.LogicalBytes)throw new IOException("Backup length changed.");
          string sourceHash=HashStream(source,token),destinationHash=HashStream(destination,token);
          if(sourceHash!=destinationHash)throw new IOException("Backup hash mismatch; source retained.");
          ValidateExpected(sourceHandle,expected);Info destinationInfo=Read(destinationHandle);
          if(destinationInfo.Links!=1||(destinationInfo.Attr&0x10)!=0)throw new IOException("Backup target unsafe.");
          receipt.BackupPath=backupPath;receipt.BackupIdentity=Key(destinationInfo);receipt.BackupAncestorIdentity=destinationLease.AncestorIdentity;receipt.Sha256=sourceHash;receipt.Bytes=copied;
          observer("BackupVerified",receipt);token.ThrowIfCancellationRequested();
          ValidateExpected(sourceHandle,expected);observer("DeleteStarted",receipt);token.ThrowIfCancellationRequested();
          MarkDeleted(sourceHandle); // Same source handle used for reading, verification and disposition.
      }else{ValidateExpected(sourceHandle,expected);observer("DeleteStarted",receipt);token.ThrowIfCancellationRequested();MarkDeleted(sourceHandle);}
     }
    }
   }
   receipt.Deleted=true;return receipt;
   }finally{
    // Keep destination file AND ancestors held until the source handle is closed.
    // A cleanup failure after commit must not be mistaken for a retained source.
    DisposeFixtureResource(destination,receipt);DisposeFixtureResource(destinationHandle,receipt);DisposeFixtureResource(destinationLease,receipt);
   }
  }
  // Restore is create-new only. The verified backup is never removed or overwritten.
  // Copy into a unique partial file, hash/flush, then rename the SAME held handle with ReplaceIfExists=false.
  public static FixtureReceipt RestoreFixture(FileRecord backup,string artifactRoot,string targetPath,string targetRoot,string targetAncestor,string expectedHash,CancellationToken token){
   string artifacts=Canonical(artifactRoot),backupRoot=Canonical(backup.Root),target=Canonical(targetPath),root=Canonical(targetRoot);
   if(!Within(backupRoot,artifacts)||!System.IO.Path.GetFileName(backupRoot).StartsWith("disk-backup-fixture-",StringComparison.Ordinal)||!File.Exists(System.IO.Path.Combine(backupRoot,".memoryclear-fixture"))||!Within(root,artifacts)||!System.IO.Path.GetFileName(root).StartsWith("disk-fixture-",StringComparison.Ordinal)||!File.Exists(System.IO.Path.Combine(root,".memoryclear-fixture"))||!Within(target,root))throw new IOException("Marked separate fixture source and restore roots required.");
   string name=System.IO.Path.GetFileName(target);if(name==".memoryclear-fixture"||name.StartsWith("journal-",StringComparison.OrdinalIgnoreCase)||name.StartsWith("restore-",StringComparison.OrdinalIgnoreCase))throw new IOException("Restore evidence protected.");
   if(String.IsNullOrEmpty(expectedHash)||expectedHash.Length!=64)throw new IOException("Expected backup hash required.");
   string partial=System.IO.Path.Combine(System.IO.Path.GetDirectoryName(target),"restore-"+Guid.NewGuid().ToString("N")+".partial");
   token.ThrowIfCancellationRequested();
   using(var sourceLease=new DirectoryLease(System.IO.Path.GetDirectoryName(backup.Path),backupRoot))
   using(var destinationLease=new DirectoryLease(System.IO.Path.GetDirectoryName(target),root)){
    if(sourceLease.AncestorIdentity!=backup.AncestorIdentity||destinationLease.AncestorIdentity!=targetAncestor)throw new IOException("Restore ancestor changed.");
    if(File.Exists(target)||Directory.Exists(target))throw new IOException("Restore conflict: destination exists; no overwrite.");
    using(SafeFileHandle sourceHandle=CreateFile(Extended(Canonical(backup.Path)),0x80000000|0x80,0,IntPtr.Zero,3,0x00200000,IntPtr.Zero)){
     if(sourceHandle.IsInvalid)throw new Win32Exception();ValidateExpected(sourceHandle,backup);
     using(var source=new FileStream(sourceHandle,FileAccess.Read,65536,false)){
      if(HashStream(source,token)!=expectedHash)throw new IOException("Backup hash changed; restore refused.");source.Position=0;
      using(SafeFileHandle destinationHandle=CreateFile(Extended(partial),0xC0000000|0x10000|0x80,0,IntPtr.Zero,1,0x00200000|0x80000000,IntPtr.Zero)){
       if(destinationHandle.IsInvalid)throw new Win32Exception();ExactPath(destinationHandle,partial);
       using(var destination=new FileStream(destinationHandle,FileAccess.ReadWrite,65536,false)){
        byte[] buffer=new byte[65536];int count;long copied=0;
        while((count=source.Read(buffer,0,buffer.Length))>0){token.ThrowIfCancellationRequested();destination.Write(buffer,0,count);copied+=count;}
        destination.Flush(true);token.ThrowIfCancellationRequested();
        if(copied!=backup.LogicalBytes||HashStream(destination,token)!=expectedHash)throw new IOException("Restore copy failed verification; partial retained: "+partial);
        ValidateExpected(sourceHandle,backup);token.ThrowIfCancellationRequested();RenameNew(destinationHandle,target);ExactPath(destinationHandle,target);
        return new FixtureReceipt{BackupPath=target,BackupIdentity=Key(Read(destinationHandle)),BackupAncestorIdentity=destinationLease.AncestorIdentity,Sha256=expectedHash,Bytes=copied,Deleted=false};
       }
      }
     }
    }
   }
  }
  static void RenameNew(SafeFileHandle handle,string target){
   byte[] name=Encoding.Unicode.GetBytes(target);int offset=IntPtr.Size==8?20:12;int size=offset+name.Length+2;
   IntPtr buffer=Marshal.AllocHGlobal(size);try{
    for(int i=0;i<size;i++)Marshal.WriteByte(buffer,i,0); // ReplaceIfExists=false; RootDirectory=NULL.
    Marshal.WriteInt32(buffer,IntPtr.Size==8?16:8,name.Length);Marshal.Copy(name,0,IntPtr.Add(buffer,offset),name.Length);
    if(!SetFileInformationBuffer(handle,3,buffer,(uint)size))throw new Win32Exception();
   }finally{Marshal.FreeHGlobal(buffer);}
  }
  static void DisposeFixtureResource(IDisposable resource,FixtureReceipt receipt){if(resource==null)return;try{resource.Dispose();}catch(Exception e){receipt.CleanupWarning=(receipt.CleanupWarning??"")+e.GetType().Name+":"+e.HResult.ToString("X8")+";";}}
  public static string HashSnapshot(FileRecord expected,CancellationToken token){
   string file=Canonical(expected.Path),root=Canonical(expected.Root);if(!Within(file,root))throw new IOException("Outside hash root.");
   using(var lease=new DirectoryLease(System.IO.Path.GetDirectoryName(file),root)){
    if(lease.AncestorIdentity!=expected.AncestorIdentity)throw new IOException("Hash ancestor changed.");
    using(SafeFileHandle h=CreateFile(Extended(file),0x80000000|0x80,0,IntPtr.Zero,3,0x00200000,IntPtr.Zero)){
     if(h.IsInvalid)throw new Win32Exception();ValidateExpected(h,expected);
     using(var stream=new FileStream(h,FileAccess.Read,65536,false)){string hash=HashStream(stream,token);ValidateExpected(h,expected);return hash;}
    }
   }
  }
  public static string ReadSnapshotText(FileRecord expected){
   if(expected.LogicalBytes>16*1024*1024)throw new IOException("Text inspection size limit.");
   string file=Canonical(expected.Path),root=Canonical(expected.Root);if(!Within(file,root))throw new IOException("Outside text root.");
   using(var lease=new DirectoryLease(System.IO.Path.GetDirectoryName(file),root)){
    if(lease.AncestorIdentity!=expected.AncestorIdentity)throw new IOException("Text ancestor changed.");
    using(SafeFileHandle h=CreateFile(Extended(file),0x80000000|0x80,0,IntPtr.Zero,3,0x00200000,IntPtr.Zero)){
     if(h.IsInvalid)throw new Win32Exception();ValidateExpected(h,expected);
     using(var stream=new FileStream(h,FileAccess.Read,65536,false))using(var reader=new StreamReader(stream,new UTF8Encoding(false,true),true)){
      string text=reader.ReadToEnd();ValidateExpected(h,expected);return text;
     }
    }
   }
  }
  static string HashStream(FileStream stream,CancellationToken token){
   stream.Position=0;byte[] buffer=new byte[65536];int count;
   using(var hash=SHA256.Create()){while((count=stream.Read(buffer,0,buffer.Length))>0){token.ThrowIfCancellationRequested();hash.TransformBlock(buffer,0,count,buffer,0);}hash.TransformFinalBlock(new byte[0],0,0);return BitConverter.ToString(hash.Hash).Replace("-","");}
  }
  static void ValidateExpected(SafeFileHandle h,FileRecord expected){
   Info i=Read(h);ExactPath(h,Canonical(expected.Path));Standard st;if(!GetFileInformationByHandleEx(h,1,out st,(uint)Marshal.SizeOf(typeof(Standard))))throw new Win32Exception();
   long written=((long)i.Written.dwHighDateTime<<32)|(uint)i.Written.dwLowDateTime;
   if((i.Attr&0x10)!=0||i.Links!=1||st.Links!=1||st.Pending!=0||st.Directory!=0||Key(i)!=expected.Identity||written!=expected.LastWriteFileTime||st.End!=expected.LogicalBytes||st.Allocation!=expected.AllocatedBytes)throw new IOException("File changed, linked or unsafe; source retained.");
  }
  static void MarkDeleted(SafeFileHandle h){var disposition=new Disposition{Delete=true};if(!SetFileInformationByHandle(h,4,ref disposition,(uint)Marshal.SizeOf(typeof(Disposition))))throw new Win32Exception();}
  [DllImport("advapi32.dll",SetLastError=true)] static extern uint GetSecurityInfo(SafeFileHandle handle,int type,uint information,out IntPtr owner,out IntPtr group,out IntPtr dacl,out IntPtr sacl,out IntPtr descriptor);
  [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);
  static void RequireOwnFile(SafeFileHandle handle){
   IntPtr owner,group,dacl,sacl,descriptor;uint result=GetSecurityInfo(handle,1,1,out owner,out group,out dacl,out sacl,out descriptor);
   if(result!=0)throw new Win32Exception((int)result);
   try{if(owner==IntPtr.Zero||new System.Security.Principal.SecurityIdentifier(owner).Value!=System.Security.Principal.WindowsIdentity.GetCurrent().User.Value)throw new IOException("File is not owned by the current user.");}finally{if(descriptor!=IntPtr.Zero)LocalFree(descriptor);}
  }
  // Separate, narrow production capability. Fixture APIs and their markers remain unchanged.
  // No recursive scope, caller-selected root, ACL change, administrator token or force-close.
  public static string OwnTempRoot(){
   using(var identity=System.Security.Principal.WindowsIdentity.GetCurrent()){
    string sid=identity.User.Value;
    bool userSid=sid.StartsWith("S-1-5-21-",StringComparison.Ordinal)||sid.StartsWith("S-1-12-1-",StringComparison.Ordinal);
    if(!userSid||Process.GetCurrentProcess().SessionId==0||new System.Security.Principal.WindowsPrincipal(identity).IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator))throw new IOException("Portable cleanup requires a non-elevated interactive user token.");
   }
   string local=Canonical(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));
   string root=Canonical(System.IO.Path.Combine(local,"Temp"));
   string windows=Environment.GetFolderPath(Environment.SpecialFolder.Windows);
   if(String.IsNullOrEmpty(windows)||!String.Equals(System.IO.Path.GetPathRoot(root),System.IO.Path.GetPathRoot(windows),StringComparison.OrdinalIgnoreCase))throw new IOException("Temp must be on the Windows volume.");
   using(var lease=new DirectoryLease(root,root)){}return root;
  }
  public static void ValidateOwnTemp(FileRecord expected,int minimumDays){
   string root=OwnTempRoot(),file=Canonical(expected.Path);
   if(minimumDays<3||minimumDays>365||!String.Equals(Canonical(expected.Root),root,StringComparison.OrdinalIgnoreCase)||!String.Equals(System.IO.Path.GetDirectoryName(file),root,StringComparison.OrdinalIgnoreCase))throw new IOException("Only top-level user Temp files are supported.");
   string ext=System.IO.Path.GetExtension(file);
   if(!String.Equals(ext,".tmp",StringComparison.OrdinalIgnoreCase)&&!String.Equals(ext,".log",StringComparison.OrdinalIgnoreCase))throw new IOException("No reviewed Temp rule for this file type.");
   if((expected.Attributes&(UnsafeAttributes|0x10|1|2|4))!=0||expected.Links!=1||expected.LogicalBytes>64*1024*1024||DateTime.FromFileTimeUtc(expected.LastWriteFileTime)>DateTime.UtcNow.AddDays(-minimumDays))throw new IOException("Recent, linked, oversized or protected Temp file.");
   using(var lease=new DirectoryLease(root,root)){
    if(expected.AncestorIdentity!=lease.AncestorIdentity)throw new IOException("Temp ancestors changed.");
    using(var handle=CreateFile(Extended(file),0x20000|0x80,0,IntPtr.Zero,3,0x00200000,IntPtr.Zero)){
     if(handle.IsInvalid)throw new Win32Exception();ValidateExpected(handle,expected);if((Read(handle).Attr&(1|2|4))!=0)throw new IOException("Protected Temp attributes.");RequireOwnFile(handle);
    }
   }
  }
  public static FixtureReceipt ExecuteOwnTemp(FileRecord expected,int minimumDays,string hash,CancellationToken token,Action<string,FixtureReceipt> observer){
   ValidateOwnTemp(expected,minimumDays);if(observer==null||String.IsNullOrEmpty(hash)||hash.Length!=64)throw new IOException("Frozen hash and durable observer required.");
   string root=OwnTempRoot(),file=Canonical(expected.Path);var receipt=new FixtureReceipt{Bytes=expected.LogicalBytes};token.ThrowIfCancellationRequested();
   using(var lease=new DirectoryLease(root,root)){
    if(expected.AncestorIdentity!=lease.AncestorIdentity)throw new IOException("Temp ancestors changed.");
    using(var handle=CreateFile(Extended(file),0x80000000|0x10000|0x20000|0x80,0,IntPtr.Zero,3,0x00200000,IntPtr.Zero)){
     if(handle.IsInvalid)throw new Win32Exception();ValidateExpected(handle,expected);if((Read(handle).Attr&(1|2|4))!=0)throw new IOException("Protected Temp attributes.");RequireOwnFile(handle);
     using(var stream=new FileStream(handle,FileAccess.Read,65536,false)){
      if(HashStream(stream,token)!=hash)throw new IOException("Temp content changed; retained.");
      observer("SourceLocked",receipt);token.ThrowIfCancellationRequested();ValidateExpected(handle,expected);
      observer("DeleteStarted",receipt);token.ThrowIfCancellationRequested();MarkDeleted(handle);
     }
    }
   }
   receipt.Deleted=true;return receipt;
  }
  public sealed class TempLedger : IDisposable {
   DirectoryLease lease;FileStream stream;
   public TempLedger(string projectRoot,string id):this(projectRoot,id,"temp-operation"){}
   public TempLedger(string projectRoot,string id,string prefix){
    if(prefix!="temp-operation"&&prefix!="memory-operation")throw new IOException("Unsupported journal prefix.");
    if(id==null||id.Length!=32||!System.Text.RegularExpressions.Regex.IsMatch(id,"^[a-f0-9]{32}$"))throw new IOException("Invalid journal ID.");
    projectRoot=Canonical(projectRoot);string directory=System.IO.Path.Combine(projectRoot,".data");
    try{using(var parent=new DirectoryLease(projectRoot,projectRoot)){Directory.CreateDirectory(directory);lease=new DirectoryLease(directory,directory);}
     string path=System.IO.Path.Combine(directory,prefix+"-"+id+".jsonl");
     var handle=CreateFile(Extended(path),0xC0000000|0x80,1,IntPtr.Zero,1,0x00200000|0x80000000,IntPtr.Zero);
     if(handle.IsInvalid){handle.Dispose();throw new Win32Exception();}try{ExactPath(handle,path);stream=new FileStream(handle,FileAccess.Write,65536,false);}catch{handle.Dispose();throw;}
    }catch{Dispose();throw;}
   }
   public void Append(string line){byte[] bytes=Encoding.UTF8.GetBytes(line+"\n");if(stream==null||stream.Length+bytes.Length>16*1024*1024)throw new IOException("Journal unavailable or full.");stream.Write(bytes,0,bytes.Length);stream.Flush(true);}
   public void Dispose(){try{if(stream!=null)stream.Dispose();}finally{if(lease!=null)lease.Dispose();stream=null;lease=null;}}
  }
  static FileRecord SnapshotHeld(string file,string root){uint attr=GetFileAttributes(Extended(file));if(attr==UInt32.MaxValue)throw new Win32Exception();if((attr&(UnsafeAttributes|0x10))!=0)throw new IOException("Protected entry or directory.");
   using(SafeFileHandle h=CreateFile(Extended(file),0x80,7,IntPtr.Zero,3,0x00200000,IntPtr.Zero)){
    if(h.IsInvalid)throw new Win32Exception();Info i=Read(h);ExactPath(h,file);Standard st;if(!GetFileInformationByHandleEx(h,1,out st,(uint)Marshal.SizeOf(typeof(Standard))))throw new Win32Exception();
    if(st.Pending!=0||st.Directory!=0)throw new IOException("Pending deletion or directory.");
    return new FileRecord{Path=file,Root=root,Identity=Key(i),LogicalBytes=st.End,AllocatedBytes=st.Allocation,Links=i.Links,Attributes=i.Attr,LastWriteFileTime=((long)i.Written.dwHighDateTime<<32)|(uint)i.Written.dwLowDateTime};
   }
  }
  public static ScanResult Scan(string[] roots,long minimumBytes,int maximumRows,int maximumEntries,int seconds,CancellationToken token){
   return ScanPage(roots,minimumBytes,maximumRows,maximumEntries,seconds,0,token);
  }
  public static ScanResult ScanPage(string[] roots,long minimumBytes,int maximumRows,int maximumEntries,int seconds,int offset,CancellationToken token){
   return ScanFilteredPage(roots,minimumBytes,Int64.MaxValue,new string[0],maximumRows,maximumEntries,seconds,offset,token);
  }
  public static ScanResult ScanFilteredPage(string[] roots,long minimumBytes,long maximumWriteTime,string[] extensions,int maximumRows,int maximumEntries,int seconds,int offset,CancellationToken token){
   if(maximumRows<1||maximumRows>5000||maximumEntries<1||maximumEntries>100000||seconds<1||seconds>120||minimumBytes<0)throw new ArgumentException("Scan budget out of bounds.");
   if(offset<0||offset>100000)throw new ArgumentException("Page offset out of bounds.");
   if(maximumWriteTime<0||extensions==null||extensions.Length>16)throw new ArgumentException("Invalid age/type filter.");
   var allowedExtensions=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   foreach(string extension in extensions){if(!System.Text.RegularExpressions.Regex.IsMatch(extension??"",@"^\.[a-zA-Z0-9]{1,12}$"))throw new ArgumentException("Invalid extension filter.");allowedExtensions.Add(extension);}
   var result=new ScanResult{Offset=offset};var watch=Stopwatch.StartNew();var seen=new HashSet<string>(StringComparer.Ordinal);var rootsSeen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   foreach(string input in roots){if(token.IsCancellationRequested){result.Cancelled=true;break;}string root;
    try{root=Canonical(input);}catch(Exception e){Issue(result,e);continue;}if(!rootsSeen.Add(root))continue;
    var pending=new Stack<string>();pending.Push(root);string rootIdentity=null;
    while(pending.Count>0){if(token.IsCancellationRequested){result.Cancelled=true;break;}if(result.Visited>=maximumEntries||watch.Elapsed.TotalSeconds>=seconds){result.Truncated=true;break;}
     string dir=pending.Pop();try{using(var lease=new DirectoryLease(dir,root)){
      if(rootIdentity==null)rootIdentity=lease.RootIdentity;else if(rootIdentity!=lease.RootIdentity)throw new IOException("Root identity changed.");
      using(var iterator=Directory.EnumerateFileSystemEntries(dir).GetEnumerator()){while(iterator.MoveNext()){
       if(token.IsCancellationRequested){result.Cancelled=true;break;}if(result.Visited>=maximumEntries||watch.Elapsed.TotalSeconds>=seconds){result.Truncated=true;break;}
       result.Visited++;string file=Canonical(iterator.Current);uint attr=GetFileAttributes(Extended(file));
       if(attr==UInt32.MaxValue){Issue(result,new Win32Exception());continue;}if((attr&UnsafeAttributes)!=0){result.Skipped++;continue;}
       if((attr&0x10)!=0){if(pending.Count>=maximumEntries){result.Truncated=true;break;}pending.Push(file);continue;}
       try{FileRecord item=SnapshotHeld(file,root);item.AncestorIdentity=lease.AncestorIdentity;if(item.Links!=1){result.Skipped++;continue;}if(!seen.Add(item.Identity)){result.Duplicates++;continue;}
        if(item.LogicalBytes<minimumBytes||item.LastWriteFileTime>maximumWriteTime||(allowedExtensions.Count>0&&!allowedExtensions.Contains(System.IO.Path.GetExtension(file))))continue;result.LogicalBytes+=item.LogicalBytes;result.AllocatedBytes+=item.AllocatedBytes;
        int match=result.Matched++;if(match<offset)continue;
        if(result.Files.Count<maximumRows)result.Files.Add(item);else{result.Truncated=true;result.HasMore=true;}
       }catch(Exception e){Issue(result,e);}
      }}
     }}catch(Exception e){Issue(result,e);}if(result.Cancelled||result.Visited>=maximumEntries||watch.Elapsed.TotalSeconds>=seconds)break;
    }
    if(result.Cancelled||result.Visited>=maximumEntries||watch.Elapsed.TotalSeconds>=seconds)break;
   }
   watch.Stop();result.Seconds=watch.Elapsed.TotalSeconds;return result;
  }
  static void Issue(ScanResult result,Exception e){result.Skipped++;if(result.Issues.Count<100)result.Issues.Add(e.GetType().Name+":"+e.HResult.ToString("X8"));}
 }
}
