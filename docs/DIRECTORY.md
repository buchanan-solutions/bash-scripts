# Bash Scripts Directory

- [Bash Scripts Directory](#bash-scripts-directory)
  - [env\_vars.sh](#env_varssh)
    - [envcheck()](#envcheck)
    - [envgen()](#envgen)
  - [combine-files.sh](#combine-filessh)
    - [combine\_files()](#combine_files)
  - [dockersummary.sh](#dockersummarysh)
    - [dockersummary()](#dockersummary)
  - [list-directory.sh](#list-directorysh)
    - [list\_dir()](#list_dir)
  - [text-search.sh](#text-searchsh)
    - [text\_search()](#text_search)



Below is a listing of all bash scripts, a short explanation, and a brief example for how to use each script.

Most scripts support a `--help` (or `-h`) flag. Passing it does not run the command; instead it prints a help block with up-to-date usage and examples. When in doubt, run the script or function with `--help` to see the latest options and examples.

---

## env_vars.sh

Helpers for reading and generating variables in a `.env` file in the current directory.

### envcheck()

Checks whether a variable is set in the current directory’s `.env` file. Prints the variable’s value if found, or a warning if missing or if `.env` is absent.

**Example:**

```bash
envcheck API_KEY
envcheck --help
```

### envgen()

Generates a random string and writes it into `.env` for the given variable name. If the variable already exists, its value is replaced. Optional second argument is length in characters (default 24). Creates `.env` if it does not exist. Values are URL-safe (no `=`, `+`, `/`).

**Example:**

```bash
envgen API_KEY
envgen JWT_SECRET 40
envgen --help
```

---

## combine-files.sh

Combines text files from one or more paths into a single `combined.txt`. Supports directories and individual files, optional git-only mode (staged/unstaged changes), and ignore patterns (folder- or file-specific, including regex).

**Example:**

```bash
combine_files src/lib/cms
combine_files . --git-changes
combine_files -d src/lib/cms -f src/lib/utils.js -i node_modules
combine_files --help
```

### combine_files()

When the script is sourced (e.g. via bootstrap), this is the function you call. It accepts paths (with optional `-d`/`-f`), `--git-changes`, and `-i <pattern>` for ignore rules. Run `combine_files --help` for full usage and examples.

---

## dockersummary.sh

Prints a formatted table of running Docker containers (name, status, created, ports). Optional filter narrows the list by name. When no filter is given, includes a “stack” column from Compose project labels.

**Example:**

```bash
dockersummary
dockersummary myapp
```

### dockersummary()

Takes an optional filter string. With no arguments, lists all running containers with stack info; with one argument, lists only containers whose name matches the filter. Output is tabular via `column -t`.

---

## list-directory.sh

Prints a tree-like directory listing with connectors (├──, └──) and indentation. Respects `.gitignore` when run inside a Git repo. Supports per-directory flags (e.g. max depth, structure-only, files only at a given level) via `directory:flags` syntax or a flags file.

**Example:**

```bash
list_dir
list_dir src
list_dir . src lib
list_dir src "pg_data:-d 1 -s" "logs:-f 2"
list_dir -ff flags.txt src
list_dir --help
```

### list_dir()

When sourced, this is the function you call. Accepts directory paths, optional `directory:flags` arguments (in double quotes), and `-ff <file>` to load flags from a file. Run `list_dir --help` for full options and examples.

---

## text-search.sh

Recursively searches for unique regex matches and groups results by match, listing which files contain each match. Supports a root folder, default and custom exclude directories, and an option to disable default excludes.

**Example:**

```bash
text_search 'process\.env\.[A-Za-z0-9_]+'
text_search -f src -i "coverage,.cache" 'import\s+.*from'
text_search --help
```

### text_search()

When sourced, this is the function you call. Requires a regex as the pattern; optional `-f <folder>`, `-i <dir1,dir2,...>` to add exclude dirs, and `-ignore-default-exclude`. Run `text_search --help` for full usage.
