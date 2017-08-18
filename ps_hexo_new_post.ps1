# ȯ�溯�� BLOG_PATH�� ������ ��α� root ��η� �̵�
cd $env:blogpath

#input���� �� ���� ������ �޴´�. 
$title = Read-Host 'Enter Title'

# ���� : hexo new draft '����'
$command = [string]::Format('hexo new draft "{0}"', $title)
$out = Invoke-Expression $command

# ������ ������ �̸��� ��θ� �����Ѵ�.
$out = $out.Replace("INFO  Created: ", "")

# ������ ������ gvim���� ����!
$new_file_path = [System.IO.Path]::Combine($PSScriptRoot, $out)
gvim.exe $new_file_path
