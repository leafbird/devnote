# ���� ��ũ��Ʈ�� ���� ��θ� ��´�.
$blog_path = (Get-Item -Path ".\" -Verbose).FullName

# ��� Ȯ��
"blog path : $blog_path"

# ���� ��θ� ȯ�溯���� ���(���� ����)
[Environment]::SetEnvironmentVariable("blogpath", $blog_path, "User")

# output result
"Environment Variable update. {0} = {1}" -f "blogpath", $blog_path

# pause
Write-Host "Press any key to continue ..."
$x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
