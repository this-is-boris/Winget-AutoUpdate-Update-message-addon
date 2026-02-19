## WAU Dialog Templates

This folder contains base XAML templates for future WAU dialog windows.

- Copy a template file
- Rename it for your scenario
- Keep control names (`x:Name`) if PowerShell code references them
- Move final dialog files to `mods/dialogs` when needed

Manual behavior:

- WAU reads dialog files only from `mods/dialogs`.
- Files in `mods/templates` are examples/templates only.
- To use a template, manually copy it to `mods/dialogs` and rename to the expected file name.
- If a dialog file is missing in `mods/dialogs`, built-in fallback templates from `_Mods-Functions.ps1` are used.

Current templates:

- `PostponeDialog.template.xaml`
- `UpdateStartingNotification.template.xaml`

PowerShell example (manual copy to `mods/dialogs`):

```powershell
New-Item -Path "C:\Program Files\Winget-AutoUpdate\mods\dialogs" -ItemType Directory -Force
Copy-Item "C:\Program Files\Winget-AutoUpdate\mods\templates\PostponeDialog.template.xaml" "C:\Program Files\Winget-AutoUpdate\mods\dialogs\PostponeDialog.xaml" -Force
Copy-Item "C:\Program Files\Winget-AutoUpdate\mods\templates\UpdateStartingNotification.template.xaml" "C:\Program Files\Winget-AutoUpdate\mods\dialogs\UpdateStartingNotification.xaml" -Force
```
