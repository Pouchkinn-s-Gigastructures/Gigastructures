# Gigastructures

## Installing from Github

In order to use the Github version of Gigastructures, download the zip version of the code as seen in the image:
![image](https://github.com/Pouchkinn-s-Gigastructures/Gigastructures/assets/8443014/3e8f3918-eb97-410c-9e12-ee46a3d2fd53)

Navigate to `Documents/Paradox Interactive/Stellaris/mod/` (or wherever you have your stellaris folder or custom mods folder if you've changed it manually) and unzip the contents of the folder (the zip should contain a folder called Gigastructures-Live-Branch) into your mod folder.

Irony Mod Manager will autogenerate the .mod file needed to locate the mod, so if using that the next steps are not needed, just launch Irony. [Irony can be found here](https://bcssov.github.io/IronyModManager/).

If using the base paradox launcher, you will then need to create another (text) file called Gigastructures-Live-Branch.mod with the following contents:

```
path="mod/Gigastructures-Live-Branch" 
name="Gigastructural Engineering & More (Github)"
picture="thumbnail.png"
remote_file_id="1121692237"
tags={
    "Gameplay"
    "Megastructures"
}
supported_version="3.9.*"
```

Place the .mod file in `Documents/Paradox Interactive/Stellaris/mod/`. That is *alongside* the Gigastructures folder with the mod content, not inside it.

After that you should be good to go and can find the mod in your launcher of choice. [See also the Wiki page on how local mods work.](https://stellaris.paradoxwikis.com/Modding#Mod_management)

It is also possible to clone the repository through usual Github methods into the `Documents/Paradox Interactive/Stellaris/mod/` folder, create the necessary .mod file or generate it, and keep the mod up to date with Github tools. See [for example this page](https://docs.github.com/en/desktop/adding-and-cloning-repositories/cloning-a-repository-from-github-to-github-desktop). Getting updates for a local copy is much easier this way.

