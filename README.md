# Cooldown Companion
An addon that allows you to create custom panels to track spell and item cooldowns with various styling options.

## Local development

This repo is a workspace that contains two WoW addon folders:

- `CooldownCompanion`
- `CooldownCompanion_Config`

For a live local install, link both folders into the same WoW AddOns directory:

```powershell
New-Item -ItemType SymbolicLink -Path "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\CooldownCompanion" -Target "C:\Users\nicho\Desktop\Cooldown-Companion\CooldownCompanion"
New-Item -ItemType SymbolicLink -Path "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\CooldownCompanion_Config" -Target "C:\Users\nicho\Desktop\Cooldown-Companion\CooldownCompanion_Config"
```

## Libraries

Thank you to all the libraries that make the addon possible 🙏

[Ace3](https://www.wowace.com/projects/ace3)

[LibDBIcon](https://www.wowace.com/projects/libdbicon-1-0)

[LibDataBroker](https://www.wowace.com/projects/libdatabroker-1-1)

[LibDeflate](https://www.wowinterface.com/downloads/fileinfo.php?id=25453)

[LibSharedMedia](https://www.wowace.com/projects/libsharedmedia-3-0)

[LibCustomGlow](https://www.curseforge.com/wow/addons/libcustomglow)
