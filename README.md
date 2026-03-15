# Bash Scripts

A collection of production-ready bash scripts for directory navigation, file manipulation, and project management tasks.

## Quick Start

Clone this repository into your home directory:

```bash
git clone https://github.com/buchanan-solutions/bash-scripts ~/scripts
```

Add the bootstrap script to your shell startup file so all commands and aliases are available in every new terminal:

```bash
echo 'if [ -f "$HOME/scripts/bootstrap.sh" ]; then source "$HOME/scripts/bootstrap.sh"; fi' >> ~/.bashrc
```

Reload your current terminal session so the changes take effect immediately:

```bash
source ~/.bashrc
```

Alternatively, you can load the scripts just for the current shell without changing any config:

```bash
source "$HOME/scripts/bootstrap.sh"
```

## Requirements

- Bash 4.0 or higher
- `realpath` command (usually included in GNU coreutils)
- Git (optional, for `.gitignore` support in `list-directory.sh`)

## License

See [LICENSE](LICENSE) file for details.
