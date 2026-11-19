<p align="center">
  <img width="70%" src="assets/banner.png" alt="Banner">
</p>
<p align="center">
  <b>A key remapping utility for macOS.</b>
</p>

## About
MacOS lacks a native utility for simple and fast key remapping.
There are plenty of solutions for this problem, even so I decided to create my own.
Unlike similar applications, Keywi doesn't need to load kernel extension, utilize
Accessibility API or even disable Sistem Integrity Protection. Three things I am
not comfortable allowing a simple key remapping utility to do.

Yes, this makes Keywi limited feature-wise. There is no custom multi-key shortcuts,
for example. But if you want to simply map one key to another, you're in the right place.

## Features

Keywi can:
- Remap keys instantly via App or CLI
- Preserve mappings after logout or reboot
- Import and export mappings
- Run natively on Intel, and Apple Silicon
- Do all this without impacting performance

Keywi does NOT require:
- Itself running in the background
- Loading kernel extensions
- Access to the Accessibility-API
- Disabled System Integrity Protection
- Root privileges

## Installation

### App

Download the latest release from the [releases section](https://github.com/randmeer/keywi/releases)
of this repository.

That's it, just double-click on the downloaded Application to open it.
You might want to move it in your /Applications folder, just to keep everything in one place.

The App is a so-called "Universal Application", meaning the executable inside determines
your processor architecture and chooses the respective binary. This means Keywi runs natively
on both x86 and ARM mac's.

### CLI

First, clone this repository
```
git clone https://github.com/randmeer/keywi
cd keywi
```

Then install using Makefile
```
sudo make install
```

## Usage

### App

[Todo]

### CLI

`keywi set [source key] [destination key]` to map

`keywi clear` to clear mappings

`keywi get` to see mappings

`keywi --version` to see the installed version


# Developement

## Building the App

First, clone this repository
```
git clone https://github.com/randmeer/keywi
cd keywi
```

Then build using Makefile
```
make build
```

## Versioning

The shared version is stored in `VERSION` and is written into the app bundle and CLI installation. Update it for a release, then create a matching Git tag such as `v0.1.1`. The app uses the Git commit count as its build number by default; override it with `make BUILD_NUMBER=42 build` when needed. The CLI reports the shared version with `keywi --version`.

## FAQ

* > Help! I accidentally mapped some letter keys and can't type out `keywi -clear` anymore.

  Either copy the command from the usage section and paste it into your terminal, or simply delete 
  `~/Library/LaunchAgents/tv.rande.keywi.plist` using Finder and log out and in again.

* > Why do I need sudo to install Keywi-cli?? The main selling point is that it doesn't need sudo!
  
  Well, macOS has no local binary folder in its default PATH, which would be the only binary folder
  make has permission to write in without sudo. I will implement adding a local binary folder to PATH,
  but for now this is the way. `sudo make install` just copies keywi into `/usr/local/bin`.

* > It says "No dependencies" on the package but the CLI requires Python, duh.
  
  If you have the necessity to use a _Command Line Interface_, but don't have Python installed,
  You probably are skilled enough to rewrite this in C. I will gladly accept your pull request.
  Open Source, _duh_.

* > Does it work on Windows?

  I have none in my Basement and cannot test that.

* > Does it work on Linux?

  Absolu- Can y'all read??

* > Where can I report a bug / request a Feature?
  
  Open a GitHub issue. Alternatively tell your Mom, she has my number anyway.

* > How can I contribute to Keywi?

  Read the "Developement" section and open a pull request. There is no code of
  conduct, I'm grateful if I get a single one.

* > Keywi remapped the wrong keys and I accidentally divorced my wife,
  > reported my son to the Police and booked a flight to northern China,
  > You're going to pay for this!!

  Nuh-uh, License says no.
