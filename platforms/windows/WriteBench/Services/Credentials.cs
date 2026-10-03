using System.IO;
using System.Security.Cryptography;
using System.Text;
namespace WriteBench;

// DPAPI binds the encrypted credential to the current Windows account.
public sealed class Credentials(string? directory = null)
{
    readonly string folder = directory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WriteBench", "Credentials");
    string PathName => Path.Combine(folder, "deepseek.dpapi");
    public string Load() => File.Exists(PathName) ? Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(PathName), null, DataProtectionScope.CurrentUser)) : "";
    public void Save(string key)
    {
        Directory.CreateDirectory(folder);
        byte[] bytes = Encoding.UTF8.GetBytes(key.Trim());
        try
        {
            var encrypted = ProtectedData.Protect(bytes, null, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(PathName + ".tmp", encrypted);
            File.Move(PathName + ".tmp", PathName, true);
        }
        finally { CryptographicOperations.ZeroMemory(bytes); }
    }
    public void Forget() { if (File.Exists(PathName)) File.Delete(PathName); }
}
