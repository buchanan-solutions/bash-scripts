# Bash Scripts

A collection of production-ready bash scripts for directory navigation, file manipulation, and project management tasks.

## Installation

Clone this repository into your home directory:

```bash
git clone https://github.com/buchanan-solutions/bash-scripts ~/scripts
```

## Available Scripts

### `list-directory.sh`

Prints a tree-like directory structure with visual connectors and proper indentation. Supports per-directory flags for fine-grained control over recursion behavior.

**Features:**
- Visual tree output with Unicode connectors (├──, └──)
- Respects `.gitignore` rules when run in a Git repository
- Per-directory depth limits and filtering options
- Configurable via command-line flags or flags file

**Usage:**
```bash
# Show current directory
~/scripts/list-directory.sh .

# Show specific directories with depth limits
~/scripts/list-directory.sh . "./data:-d 1 -s" "./logs:-d 2"

# Use flags file
~/scripts/list-directory.sh -ff flags.txt
```

**Note:** Directory:flags arguments must be wrapped in double quotes for proper parsing (e.g., `"./data:-d 1 -s"`).

### `combine-files.sh`

Combines all text files from a given directory into a single `combined.txt` file with configurable ignore patterns.

**Usage:**
```bash
~/scripts/combine-files.sh -p ./src/lib/cms -i node_modules -i tests
```

## Requirements

- Bash 4.0 or higher
- `realpath` command (usually included in GNU coreutils)
- Git (optional, for `.gitignore` support in `list-directory.sh`)

## License

See [LICENSE](LICENSE) file for details.
