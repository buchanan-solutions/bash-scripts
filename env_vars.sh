envcheck() {
    local var_name="${1-}"       # first arg, default empty
    local env_file=".env"
    local env_file_abs

    # Resolve absolute path safely
    if command -v realpath >/dev/null 2>&1; then
        env_file_abs=$(realpath "$env_file" 2>/dev/null || echo "$PWD/$env_file")
    else
        env_file_abs="$PWD/$env_file"
    fi

    # Show help if requested or no argument provided
    if [[ -z "$var_name" || "$var_name" == "--help" ]]; then
        cat <<'EOF'
Usage: envcheck VAR_NAME

Checks if VAR_NAME is set in the .env file at the current directory.
Prints the variable's value if found, or a warning if missing.
EOF
        return 0
    fi

    # Warn if .env is missing
    if [[ ! -f "$env_file" ]]; then
        echo "Warning: .env file not found at $env_file_abs"
        return 0
    fi

    # Pure Bash read loop (handles CRLF safely)
    local line
    local found=0
    while IFS='=' read -r key value || [ -n "$key" ]; do
        key="${key%%[[:space:]]*}"          # trim any trailing whitespace
        key="${key%%$'\r'}"                  # remove CR if present
        value="${value%%$'\r'}"              # remove CR if present
        if [[ "$key" == "$var_name" ]]; then
            echo "Found: $key=$value"
            found=1
            break
        fi
    done < "$env_file"

    if [[ $found -eq 0 ]]; then
        echo "Environment variable '$var_name' was NOT found in $env_file_abs"
    fi
}


envgen() {
    local var_name="$1"
    local num_chars="${2:-24}"   # default to 24 chars if not specified
    local env_file=".env"
    local env_file_abs

    # Resolve absolute path safely
    if command -v realpath >/dev/null 2>&1; then
        env_file_abs=$(realpath "$env_file" 2>/dev/null || echo "$PWD/$env_file")
    else
        env_file_abs="$PWD/$env_file"
    fi

    # Show help if requested or no argument provided
    if [[ -z "$var_name" || "$var_name" == "--help" ]]; then
        cat <<'EOF'
Usage: env_gen VAR_NAME [NUM_CHARS]

Generates a random string of NUM_CHARS (default 24) for VAR_NAME in the .env file
in the current directory. If VAR_NAME already exists, its value is replaced.

Examples:
  env_gen API_KEY
      # Adds or updates API_KEY with a new random 24-character value in .env

  env_gen JWT_SECRET 40
      # Adds/updates JWT_SECRET with a 40-character random value

- .env will be created if it does not exist.
- Random values use openssl and are URL-safe (=/+ characters removed).

EOF
        return 0
    fi

    # Ensure .env file exists
    [[ ! -f "$env_file" ]] && touch "$env_file"

    # Generate random string
    local rand_value
    rand_value=$(openssl rand -base64 $((num_chars*3/4 + 1)) | tr -d '=+/' | cut -c1-"$num_chars")

    # If variable exists, replace its value; otherwise, append to bottom
    if grep -q "^$var_name=" "$env_file"; then
        sed -i "s/^$var_name=.*/$var_name=$rand_value/" "$env_file"
        echo "Updated $var_name with a new random value (${#rand_value} characters) in: $env_file_abs"
    else
        echo "$var_name=$rand_value" >> "$env_file"
        echo "Added $var_name with a new random value (${#rand_value} characters) to: $env_file_abs"
    fi
}