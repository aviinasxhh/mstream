#!/bin/bash

CONFIG_DIR="$HOME/.mstream"
PLAYLIST_DIR="$CONFIG_DIR/playlists"
QUEUE_FILE="$CONFIG_DIR/queue.txt"
PID_FILE="$CONFIG_DIR/mpv.pid"
LOOP_FILE="$CONFIG_DIR/loop_mode"
SKIPPED_FILE="$CONFIG_DIR/skipped"
NOW_FILE="$CONFIG_DIR/now_playing"
PAUSED_FILE="$CONFIG_DIR/paused"
LOCK_FILE="$CONFIG_DIR/mstream.lock"
POS_FILE="$CONFIG_DIR/pos"
SYNC_SCRIPT="$CONFIG_DIR/sync_pos.lua"

mkdir -p "$PLAYLIST_DIR"

cat > "$SYNC_SCRIPT" << 'LUA_EOF'
local pos_file = os.getenv("MSTREAM_POS_FILE")
local last_time = 0

local function write_pos(_, value)
    if pos_file == nil or value == nil then return end
    local now = mp.get_time()
    if now - last_time >= 0.3 then
        local f = io.open(pos_file, "w")
        if f then
            f:write(string.format("%.3f", value))
            f:close()
        end
        last_time = now
    end
end

mp.observe_property("time-pos", "number", write_pos)
LUA_EOF

if command -v flock &> /dev/null; then
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        echo "Another instance of mstream is already running."
        exit 1
    fi
fi

: > "$QUEUE_FILE"
rm -f "$PID_FILE"
echo "off" > "$LOOP_FILE"
rm -f "$SKIPPED_FILE" "$NOW_FILE" "$PAUSED_FILE" "$POS_FILE"

check_dependencies() {
    printf "\033[34mChecking dependencies...\033[0m\n"
    local missing=0

    if ! command -v mpv &> /dev/null; then
        missing=1
        printf "\033[31mError: mpv is not installed.\033[0m Please install it using your system's package manager.\n"
    fi

    if ! command -v yt-dlp &> /dev/null; then
        missing=1
        printf "\033[31mError: yt-dlp is not installed.\033[0m Please install it globally (e.g. pipx install yt-dlp).\n"
    fi

    if [ "$missing" -eq 1 ]; then
        exit 1
    else
        printf "\033[32mAll dependencies are installed.\033[0m\n"
        if ! command -v curl &> /dev/null; then
            printf "\033[33mNote: curl was not found - the lyrics feature will be unavailable (bash can't do HTTPS on its own).\033[0m\n"
        fi
        sleep 0.5
    fi
}

check_dependencies

cleanup() {
    tput cnorm 2>/dev/null
    tput rmcup 2>/dev/null
    if [ -n "$WORKER_PID" ]; then
        kill "$WORKER_PID" 2>/dev/null
    fi
    if [ -f "$PID_FILE" ]; then
        kill -9 "$(cat "$PID_FILE")" 2>/dev/null
    fi
    local remaining_jobs
    mapfile -t remaining_jobs < <(jobs -p)
    if [ ${#remaining_jobs[@]} -gt 0 ]; then
        kill "${remaining_jobs[@]}" 2>/dev/null
    fi
    rm -f "$PID_FILE" "$QUEUE_FILE" "$LOOP_FILE" "$SKIPPED_FILE" "$NOW_FILE" "$PAUSED_FILE" "$POS_FILE"
    exit 0
}
trap cleanup EXIT INT TERM HUP

is_paused() {
    [ -f "$PAUSED_FILE" ]
}

player_worker() {
    while true; do
        if [ -s "$QUEUE_FILE" ]; then
            line=$(head -n 1 "$QUEUE_FILE")
            sed -i.bak '1d' "$QUEUE_FILE" && rm -f "${QUEUE_FILE}.bak"

            IFS='|' read -r vid title artist <<< "$line"
            if [ -n "$vid" ]; then
                echo "$line" > "$NOW_FILE"
                echo 0 > "$POS_FILE"

                url="https://music.youtube.com/watch?v=$vid"
                MSTREAM_POS_FILE="$POS_FILE" mpv --no-video --ytdl-format=bestaudio --script="$SYNC_SCRIPT" "$url" > /dev/null 2>&1 &
                MPV_PID=$!
                echo $MPV_PID > "$PID_FILE"
                rm -f "$SKIPPED_FILE"
                wait $MPV_PID
                status=$?
                rm -f "$PID_FILE"
                rm -f "$NOW_FILE"
                rm -f "$PAUSED_FILE"
                rm -f "$POS_FILE"

                was_skipped=0
                if [ -f "$SKIPPED_FILE" ]; then
                    was_skipped=1
                    rm -f "$SKIPPED_FILE"
                fi

                loop_mode="off"
                if [ -f "$LOOP_FILE" ]; then loop_mode=$(cat "$LOOP_FILE"); fi

                if [ "$loop_mode" = "song" ] && [ "$was_skipped" -eq 0 ]; then
                    if [ -s "$QUEUE_FILE" ]; then
                        tmp=$(mktemp)
                        echo "$line" > "$tmp"
                        cat "$QUEUE_FILE" >> "$tmp"
                        mv "$tmp" "$QUEUE_FILE"
                    else
                        echo "$line" > "$QUEUE_FILE"
                    fi
                elif [ "$loop_mode" = "queue" ]; then
                    echo "$line" >> "$QUEUE_FILE"
                fi

                if [ $status -eq 4 ] || [ $status -eq 143 ] || [ $status -eq 137 ] || [ $status -ne 0 ]; then
                    sleep 1.5
                fi
            fi
        else
            sleep 0.5
        fi
    done
}

player_worker &
WORKER_PID=$!

urlencode() {
    local string="$1" strlen encoded c o i
    strlen=${#string}
    for (( i=0; i<strlen; i++ )); do
        c="${string:i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) o="$c" ;;
            ' ') o="+" ;;
            *) printf -v o '%%%02X' "'$c" ;;
        esac
        encoded+="$o"
    done
    echo "$encoded"
}

search_song() {
    local query="$1"
    local limit="${2:-1}"
    if [[ "$query" =~ ://|^www\. ]]; then
        echo "error: links are not supported. Please search by song name instead." >&2
        return
    fi
    echo "Searching..." >&2
    local encoded_query
    encoded_query=$(urlencode "$query")
    local search_url="https://music.youtube.com/search?q=${encoded_query}&sp=EgWQAQIQAQ%3D%3D"
    local raw_output
    raw_output=$(yt-dlp --print "%(id)s|%(title)s|%(artist)s" "$search_url" --playlist-items "1:${limit}" --skip-download 2>/dev/null)

    if [ -n "$raw_output" ]; then
        echo "$raw_output"
    fi
}




do_skip() {
    if [ -f "$PID_FILE" ]; then
        touch "$SKIPPED_FILE"
        local pid
        pid=$(cat "$PID_FILE")
        if is_paused; then
            kill -CONT "$pid" 2>/dev/null
        fi
        kill -TERM "$pid" 2>/dev/null
        rm -f "$PAUSED_FILE"
        return 0
    fi
    return 1
}

do_pause() {
    if [ -f "$PID_FILE" ] && ! is_paused; then
        kill -STOP "$(cat "$PID_FILE")"
        touch "$PAUSED_FILE"
        return 0
    fi
    return 1
}

do_resume() {
    if [ -f "$PID_FILE" ] && is_paused; then
        kill -CONT "$(cat "$PID_FILE")"
        rm -f "$PAUSED_FILE"
        return 0
    fi
    return 1
}

do_loop() {
    local cur
    cur=$(cat "$LOOP_FILE" 2>/dev/null || echo "off")
    local new_mode
    case "$cur" in
        "off")  new_mode="song" ;;
        "song") new_mode="queue" ;;
        "queue") new_mode="off" ;;
        *) new_mode="off" ;;
    esac
    echo "$new_mode" > "$LOOP_FILE"
    echo "$new_mode"
}


get_elapsed_ms() {
    local pos whole frac ms
    pos=""
    [ -f "$POS_FILE" ] && IFS= read -r pos < "$POS_FILE" 2>/dev/null
    if [ -z "$pos" ]; then
        echo 0
        return
    fi
    whole="${pos%%.*}"
    frac="${pos#*.}"
    [ "$frac" = "$pos" ] && frac="000"
    frac="${frac}000"
    frac="${frac:0:3}"
    ms=$(( 10#$whole * 1000 + 10#$frac ))
    echo "$ms"
}

fetch_lyrics() {
    local title="$1" artist="$2"
    if ! command -v curl &> /dev/null; then
        echo "curl is required to reach lrclib.net over HTTPS (bash has no TLS support of its own)." >&2
        return 1
    fi
    if ! echo | grep -P '' &> /dev/null; then
        echo "GNU grep with PCRE support (-P) is required to parse the lyrics response." >&2
        return 1
    fi

    local t a url response
    t=$(urlencode "$title")
    a=$(urlencode "$artist")
    url="https://lrclib.net/api/search?track_name=${t}&artist_name=${a}"
    response=$(curl -s --max-time 10 -A "mstream-cli" "$url")

    if [ -z "$response" ] || [ "$response" = "[]" ]; then
        return 1
    fi

    local matches raw m
    mapfile -t matches < <(printf '%s' "$response" | grep -oP '"syncedLyrics"\s*:\s*"\K(\\.|[^"\\])*(?=")')
    raw=""
    for m in "${matches[@]}"; do
        if [ -n "$m" ]; then
            raw="$m"
            break
        fi
    done

    if [ -z "$raw" ]; then
        return 1
    fi

    printf '%s' "$raw" | sed \
        -e 's/\\\\/\x01/g' \
        -e 's/\\n/\n/g' \
        -e 's/\\t/\t/g' \
        -e 's/\\r//g' \
        -e 's/\\"/"/g' \
        -e 's/\\\//\//g' \
        -e 's/\x01/\\/g'
    return 0
}

parse_lrc_to_file() {
    local lrc="$1" outfile="$2"
    local tmp
    tmp=$(mktemp)
    : > "$tmp"
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[([0-9]+):([0-9]+)\.([0-9]+)\](.*)$ ]]; then
            local min sec frac text total_ms
            min=${BASH_REMATCH[1]}
            sec=${BASH_REMATCH[2]}
            frac=${BASH_REMATCH[3]}
            text="${BASH_REMATCH[4]}"
            if [ ${#frac} -eq 2 ]; then frac="${frac}0"; fi
            if [ ${#frac} -gt 3 ]; then frac="${frac:0:3}"; fi
            total_ms=$(( (10#$min * 60 + 10#$sec) * 1000 + 10#$frac ))
            printf "%d|%s\n" "$total_ms" "$text" >> "$tmp"
        fi
    done <<< "$lrc"
    sort -t'|' -k1,1n "$tmp" > "$outfile"
    rm -f "$tmp"
}

lyrics_view() {
    if [ ! -f "$NOW_FILE" ]; then
        echo "Nothing is playing."
        sleep 1
        return
    fi

    local vid title artist track_key
    IFS='|' read -r vid title artist < "$NOW_FILE"
    track_key="$vid|$title|$artist"

    clear
    printf "\033[34mFetching lyrics for %s - %s...\033[0m\n" "$title" "$artist"
    local lrc
    if ! lrc=$(fetch_lyrics "$title" "$artist"); then
        echo "No synced lyrics found for '$title' by '$artist'."
        read -r -p "(press enter to go back) "
        return
    fi

    local lyrics_tmp
    lyrics_tmp=$(mktemp)
    parse_lrc_to_file "$lrc" "$lyrics_tmp"

    if [ ! -s "$lyrics_tmp" ]; then
        echo "Lyrics were found but could not be parsed."
        rm -f "$lyrics_tmp"
        read -r -p "(press enter to go back) "
        return
    fi

    local lyric_times=() lyric_texts=()
    while IFS='|' read -r t txt; do
        lyric_times+=("$t")
        lyric_texts+=("$txt")
    done < "$lyrics_tmp"
    rm -f "$lyrics_tmp"

    local total_lines=${#lyric_times[@]}

    tput smcup 2>/dev/null
    tput civis 2>/dev/null
    clear

    local last_idx=-1
    local rows cols
    rows=$(tput lines 2>/dev/null || echo 24)
    cols=$(tput cols 2>/dev/null || echo 80)

    while true; do
        local cur_now=""
        [ -f "$NOW_FILE" ] && IFS= read -r cur_now < "$NOW_FILE" 2>/dev/null
        if [ "$cur_now" != "$track_key" ]; then
            break
        fi

        local elapsed
        elapsed=$(get_elapsed_ms)

        local cur_idx=$last_idx i
        if [ "$cur_idx" -ge 0 ] && [ "$cur_idx" -lt "$total_lines" ] && [ "${lyric_times[$cur_idx]:-0}" -gt "$elapsed" ]; then
            cur_idx=-1
        fi

        local start_search=$(( cur_idx == -1 ? 0 : cur_idx ))
        for ((i=start_search; i<total_lines; i++)); do
            if [ "${lyric_times[$i]}" -le "$elapsed" ]; then
                cur_idx=$i
            else
                break
            fi
        done
        last_idx=$cur_idx

        tput cup 0 0
        local header="$title - $artist"
        printf "\033[K\033[34m%s\033[0m\n" "${header:0:$((cols-1))}"
        printf "\033[K\033[38;5;236m────────────────────────────────────────\033[0m\n"

        local context=$(( (rows - 5) / 2 ))
        [ "$context" -lt 2 ] && context=2
        local start_i=$((cur_idx - context))
        local end_i=$((cur_idx + context))
        [ "$start_i" -lt 0 ] && start_i=0
        [ "$end_i" -ge "$total_lines" ] && end_i=$((total_lines - 1))

        for ((i=start_i; i<=end_i; i++)); do
            local txt="${lyric_texts[$i]}"
            [ -z "$txt" ] && txt=" "
            if [ "$i" -eq "$cur_idx" ]; then
                printf "\033[K\033[1;36m%s\033[0m\n" "${txt:0:$((cols-1))}"
            else
                printf "\033[K\033[2m%s\033[0m\n" "${txt:0:$((cols-1))}"
            fi
        done
        printf "\033[K\n\033[K\033[2mPress any key to go back\033[0m\n"

        if read -t 0.3 -rsn1 _key 2>/dev/null; then
            break
        fi

        if [ ! -f "$PID_FILE" ] && [ "$cur_idx" -eq $((total_lines - 1)) ]; then
            :
        fi
    done

    tput cnorm 2>/dev/null
    tput rmcup 2>/dev/null
}

print_track_table() {
    local file="$1"
    local i=1
    echo ""
    echo "    Title                               Artist"
    while IFS='|' read -r vid title artist; do
        printf "%-3s %-35s %s\n" "$i" "${title:0:34}" "$artist"
        i=$((i+1))
    done < "$file"
}

parse_index_selection() {
    local choice="$1" total="$2"
    local -n _out="$3"
    _out=()
    local token start end
    for token in $choice; do
        if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start=${BASH_REMATCH[1]}
            end=${BASH_REMATCH[2]}
            if [ "$start" -ge 1 ] && [ "$end" -le "$total" ] && [ "$start" -le "$end" ]; then
                local n
                for ((n=start; n<=end; n++)); do _out+=("$n"); done
            else
                echo "Invalid range: $token"
                return 1
            fi
        elif [[ "$token" =~ ^[0-9]+$ ]] && [ "$token" -ge 1 ] && [ "$token" -le "$total" ]; then
            _out+=("$token")
        else
            echo "Invalid input: $token"
            return 1
        fi
    done
    [ ${#_out[@]} -gt 0 ]
}

remove_tracks_by_indices() {
    local file="$1"; shift
    local indices=("$@")
    local sorted removed vid title artist ln removed_count=0
    mapfile -t sorted < <(printf '%s\n' "${indices[@]}" | sort -rnu)
    for ln in "${sorted[@]}"; do
        removed=$(sed -n "${ln}p" "$file")
        IFS='|' read -r vid title artist <<< "$removed"
        sed -i.bak "${ln}d" "$file" && rm -f "${file}.bak"
        echo "Removed '$title'"
        removed_count=$((removed_count+1))
    done
    echo "$removed_count"
}

do_queue_menu() {
    while true; do
        clear
        printf "\033[34m                 Queue\033[0m\n"
        printf "\033[38;5;236m────────────────────────────────────────\033[0m\n"

        if [ ! -s "$QUEUE_FILE" ]; then
            echo "Queue is empty."
            echo ""
            read -r -p "(press enter to go back) "
            return
        fi

        print_track_table "$QUEUE_FILE"
        echo ""
        local qopts=("Remove tracks" "Move a track" "Clear queue" "Back")
        menu_select "34" "${qopts[@]}"

        case "$MENU_RESULT" in
            "Remove tracks")
                echo ""
                read -r -e -p "Enter numbers to remove (e.g. 1 3 5 or 2-4, or blank to cancel): " choice
                if [ -z "$choice" ]; then continue; fi
                local total lines_to_remove=()
                total=$(wc -l < "$QUEUE_FILE")
                if parse_index_selection "$choice" "$total" lines_to_remove; then
                    local removed_count
                    removed_count=$(remove_tracks_by_indices "$QUEUE_FILE" "${lines_to_remove[@]}")
                    echo "Removed $removed_count track(s) from queue."
                fi
                sleep 1
                ;;
            "Move a track")
                echo ""
                local total from_pos to_pos
                total=$(wc -l < "$QUEUE_FILE")
                read -r -e -p "Move from position (1-$total, blank to cancel): " from_pos
                if [ -z "$from_pos" ]; then continue; fi
                read -r -e -p "Move to position (1-$total): " to_pos
                if ! [[ "$from_pos" =~ ^[0-9]+$ ]] || ! [[ "$to_pos" =~ ^[0-9]+$ ]] || \
                   [ "$from_pos" -lt 1 ] || [ "$from_pos" -gt "$total" ] || \
                   [ "$to_pos" -lt 1 ] || [ "$to_pos" -gt "$total" ]; then
                    echo "Invalid positions. Must be between 1 and $total."
                    sleep 1
                    continue
                fi
                if [ "$from_pos" -eq "$to_pos" ]; then
                    echo "Already at that position."
                    sleep 1
                    continue
                fi
                local line vid title artist
                line=$(sed -n "${from_pos}p" "$QUEUE_FILE")
                sed -i.bak "${from_pos}d" "$QUEUE_FILE" && rm -f "${QUEUE_FILE}.bak"
                sed -i.bak "${to_pos}i\\${line}" "$QUEUE_FILE" && rm -f "${QUEUE_FILE}.bak"
                IFS='|' read -r vid title artist <<< "$line"
                echo "Moved '$title' from #$from_pos to #$to_pos"
                sleep 1
                ;;
            "Clear queue")
                : > "$QUEUE_FILE"
                echo "Queue cleared."
                sleep 1
                return
                ;;
            "Back"|*)
                return
                ;;
        esac
    done
}


MENU_RESULT=""
MENU_INDEX=-1

menu_select() {
    local color_code="$1"
    shift
    local options=("$@")
    local selected=0
    local count=${#options[@]}

    tput civis 2>/dev/null

    local read_args=("-rsn1")
    if [ -n "$MENU_TIMEOUT" ]; then
        read_args=("-t" "$MENU_TIMEOUT" "-rsn1")
    fi

    local i
    for i in "${!options[@]}"; do
        if [ "$i" -eq "$selected" ]; then
            printf "\033[K\033[%sm▌\033[0m \033[1m%s\033[0m\n" "$color_code" "${options[$i]}"
        else
            printf "\033[K\033[38;5;236m▌\033[0m %s\n" "${options[$i]}"
        fi
    done

    while true; do
        local key
        if ! read -r "${read_args[@]}" key; then
            if [ -n "$MENU_TIMEOUT_CB" ]; then
                tput sc 2>/dev/null
                eval "$MENU_TIMEOUT_CB"
                tput rc 2>/dev/null
                if [ -n "$MENU_EXIT" ]; then
                    MENU_RESULT="__EXIT__"
                    tput cnorm 2>/dev/null
                    return
                fi
            fi
            continue
        fi

        if [ "$key" = "" ]; then
            break
        fi

        if [ "$key" = $'\033' ]; then
            local rest
            read -rsn2 rest
            case "$rest" in
                '[A')
                    if [ $selected -gt 0 ]; then
                        selected=$((selected - 1))
                    fi
                    ;;
                '[B')
                    if [ $selected -lt $((count - 1)) ]; then
                        selected=$((selected + 1))
                    fi
                    ;;
            esac

            printf "\033[%dA" "$count"

            for i in "${!options[@]}"; do
                printf "\033[2K"  
                if [ "$i" -eq "$selected" ]; then
                    printf "\033[%sm▌\033[0m \033[1m%s\033[0m\n" "$color_code" "${options[$i]}"
                else
                    printf "\033[38;5;236m▌\033[0m %s\n" "${options[$i]}"
                fi
            done
        fi
    done

    tput cnorm 2>/dev/null

    MENU_RESULT="${options[$selected]}"
    MENU_INDEX=$selected
}

do_interactive_search() {
    local query="$1"
    local target_file="${2:-$QUEUE_FILE}"
    local results
    results=$(search_song "$query" 5)
    
    if [ -z "$results" ]; then
        echo "No results found for '$query'."
        return 1
    fi

    local options=()
    local result_lines=()
    while IFS='|' read -r vid title artist; do
        result_lines+=("$vid|$title|$artist")
        local title_fmt="${title:0:34}"
        options+=("$(printf "%-35s %s" "$title_fmt" "$artist")")
    done <<< "$results"

    options+=("Cancel")

    echo ""
    menu_select "34" "${options[@]}"

    if [ "$MENU_RESULT" = "Cancel" ]; then
        echo "Cancelled."
        return 1
    fi

    local selected_line="${result_lines[$MENU_INDEX]}"
    echo "$selected_line" >> "$target_file"
    IFS='|' read -r vid title artist <<< "$selected_line"
    if [ "$target_file" = "$QUEUE_FILE" ]; then
        echo "Queued: $title by $artist"
    else
        echo "Added: $title by $artist"
    fi
    return 0
}


render_status() {
    printf "\033[K\n"

    if [ -f "$NOW_FILE" ] && [ -f "$PID_FILE" ]; then
        IFS='|' read -r vid title artist < "$NOW_FILE"
        local queue_count
        queue_count=$(wc -l < "$QUEUE_FILE" 2>/dev/null | tr -d ' ')
        local loop_mode="off"
        [ -f "$LOOP_FILE" ] && IFS= read -r loop_mode < "$LOOP_FILE" 2>/dev/null
        [ -z "$loop_mode" ] && loop_mode="off"

        local cols label track max_len
        cols=$(tput cols 2>/dev/null || echo 80)
        if is_paused; then label="Paused: "; else label="Playing: "; fi
        max_len=$(( cols - ${#label} - 1 ))
        [ "$max_len" -lt 1 ] && max_len=1
        track="$title - $artist"
        if [ "${#track}" -gt "$max_len" ]; then
            track="${track:0:$((max_len - 1))}…"
        fi

        if is_paused; then
            printf "\033[K\033[36mPaused:\033[0m \033[1m%s\033[0m\n" "$track"
        else
            printf "\033[K\033[36mPlaying:\033[0m \033[1m%s\033[0m\n" "$track"
        fi
        printf "\033[K  \033[2m%s in queue | loop: %s\033[0m\n" "$queue_count" "$loop_mode"
    elif [ -s "$QUEUE_FILE" ]; then
        printf "\033[K\033[36mLoading next track...\033[0m\n"
        printf "\033[K\n"
    else
        printf "\033[K\033[36mQueue is empty.\033[0m\n"
        printf "\033[K\n"
    fi

    printf "\033[K\033[38;5;236m────────────────────────────────────────\033[0m\n"
    printf "\033[K\n"
}

playing_mode() {
    tput smcup 2>/dev/null
    clear

    local last_now=""
    local last_queue=""
    local last_paused=""
    
    check_playing_status() {
        if [ ! -f "$PID_FILE" ] && [ ! -s "$QUEUE_FILE" ]; then
            sleep 1
            if [ ! -f "$PID_FILE" ] && [ ! -s "$QUEUE_FILE" ]; then
                MENU_EXIT=1
                return
            fi
        fi

        local current_now=""
        if [ -f "$NOW_FILE" ]; then IFS= read -r current_now < "$NOW_FILE" 2>/dev/null || true; fi
        local current_queue
        current_queue=$(wc -l < "$QUEUE_FILE" 2>/dev/null | tr -d ' ')
        local current_paused=0
        is_paused && current_paused=1

        if [ "$current_now" != "$last_now" ] || [ "$current_queue" != "$last_queue" ] || [ "$current_paused" != "$last_paused" ]; then
            tput cup 0 0
            render_status
            last_now="$current_now"
            last_queue="$current_queue"
            last_paused="$current_paused"
        fi
    }

    while true; do
        tput cup 0 0
        render_status
        last_now=""
        [ -f "$NOW_FILE" ] && IFS= read -r last_now < "$NOW_FILE" 2>/dev/null
        last_queue=$(wc -l < "$QUEUE_FILE" 2>/dev/null | tr -d ' ')
        last_paused=0
        is_paused && last_paused=1
        MENU_EXIT=""

        local menu_options=("skip")
        if is_paused; then
            menu_options+=("resume")
        else
            menu_options+=("pause")
        fi
        menu_options+=("loop" "lyrics" "queue" "add" "quit")

        MENU_TIMEOUT=1
        MENU_TIMEOUT_CB="check_playing_status"
        menu_select "31" "${menu_options[@]}"
        MENU_TIMEOUT=""
        MENU_TIMEOUT_CB=""

        if [ "$MENU_RESULT" = "__EXIT__" ]; then
            tput rmcup 2>/dev/null
            echo "Queue finished."
            return
        fi

        case "$MENU_RESULT" in
            "skip")
                do_skip
                sleep 0.5
                ;;
            "pause")
                do_pause
                ;;
            "resume")
                do_resume
                ;;
            "loop")
                do_loop > /dev/null
                ;;
            "lyrics")
                lyrics_view
                clear
                ;;
            "queue")
                clear
                do_queue_menu
                clear
                ;;
            "add")
                clear
                printf "\033[34m              Add to Queue\033[0m\n"
                printf "\033[38;5;236m────────────────────────────────────────\033[0m\n"
                local add_options=("Add a Song" "Add a Playlist" "Cancel")
                menu_select "31" "${add_options[@]}"
                
                if [ "$MENU_RESULT" = "Add a Song" ]; then
                    clear
                    read -r -e -p "Enter song name to add (leave blank to cancel): " add_query
                    if [ -n "$add_query" ]; then
                        if do_interactive_search "$add_query"; then
                            sleep 1
                        else
                            sleep 1
                        fi
                    fi
                elif [ "$MENU_RESULT" = "Add a Playlist" ]; then
                    clear
                    printf "\033[34m         Select Playlist to Add\033[0m\n"
                    printf "\033[38;5;236m────────────────────────────────────────\033[0m\n"
                    local plist_options=()
                    for f in "$PLAYLIST_DIR"/*.txt; do
                        if [ -f "$f" ]; then
                            pname=$(basename "$f" .txt)
                            tracks=$(wc -l < "$f")
                            plist_options+=("$pname ($tracks tracks)")
                        fi
                    done
                    
                    if [ ${#plist_options[@]} -eq 0 ]; then
                        echo "No playlists found."
                        sleep 1
                    else
                        plist_options+=("Cancel")
                        menu_select "34" "${plist_options[@]}"
                        if [ "$MENU_RESULT" != "Cancel" ] && [ -n "$MENU_RESULT" ]; then
                            local selected_plist="${MENU_RESULT% (*}"
                            if [ -f "$PLAYLIST_DIR/${selected_plist}.txt" ]; then
                                cat "$PLAYLIST_DIR/${selected_plist}.txt" >> "$QUEUE_FILE"
                                echo "Added playlist '$selected_plist' to queue."
                                sleep 1
                            fi
                        fi
                    fi
                fi
                clear
                ;;

            "quit")
                tput rmcup 2>/dev/null
                cleanup
                ;;
        esac
    done
}

do_interactive_playlists() {
    PLAYLIST_ACTION=""
    PLAYLIST_TARGET=""
    while true; do
        clear
        printf "\033[34m               Playlists\033[0m\n"
        printf "\033[38;5;236m────────────────────────────────────────\033[0m\n"
        local options=()
        for f in "$PLAYLIST_DIR"/*.txt; do
            if [ -f "$f" ]; then
                pname=$(basename "$f" .txt)
                tracks=$(wc -l < "$f")
                options+=("$pname ($tracks tracks)")
            fi
        done
        options+=("Create new playlist" "Delete multiple playlists" "Back")
        
        menu_select "34" "${options[@]}"
        
        local selected="$MENU_RESULT"
        if [ "$selected" = "Back" ] || [ -z "$selected" ]; then
            return
        elif [ "$selected" = "Create new playlist" ]; then
            echo ""
            read -r -e -p $'\001\033[34m\002Enter new playlist name (leave blank to cancel):\001\033[0m\002 ' new_name
            if [ -n "$new_name" ]; then
                new_name=$(echo "$new_name" | tr -cd 'A-Za-z0-9_-')
                if [ -n "$new_name" ]; then
                    touch "$PLAYLIST_DIR/${new_name}.txt"
                    echo "Created playlist '$new_name'."
                    sleep 1
                else
                    echo "Invalid name."
                    sleep 1
                fi
            fi
        elif [ "$selected" = "Delete multiple playlists" ]; then
            clear
            printf "\033[34m            Delete Playlists\033[0m\n"
            printf "\033[38;5;236m────────────────────────────────────────\033[0m\n"
            local idx=1
            local plist=()
            for f in "$PLAYLIST_DIR"/*.txt; do
                if [ -f "$f" ]; then
                    pname=$(basename "$f" .txt)
                    plist+=("$pname")
                    printf "%-3s %s\n" "$idx" "$pname"
                    idx=$((idx+1))
                fi
            done
            if [ ${#plist[@]} -eq 0 ]; then
                echo "No playlists found."
                sleep 1
                continue
            fi
            echo ""
            read -r -e -p $'\001\033[34m\002Enter numbers to delete (e.g. 1 3, or \'cancel\'):\001\033[0m\002 ' choice
            if [ "$choice" == "cancel" ] || [ -z "$choice" ]; then
                continue
            fi
            
            local to_delete=()
            if parse_index_selection "$choice" "${#plist[@]}" to_delete; then
                local sorted
                mapfile -t sorted < <(printf '%s\n' "${to_delete[@]}" | sort -rnu)
                del_count=0
                for ln in "${sorted[@]}"; do
                    idx=$((ln-1))
                    target="${plist[$idx]}"
                    rm -f "$PLAYLIST_DIR/${target}.txt"
                    echo "Deleted '$target'"
                    del_count=$((del_count+1))
                done
                echo "Deleted $del_count playlist(s)."
                sleep 1.5
            else
                sleep 1
            fi
        else
            local pname="${selected% (*}"
            while true; do
                clear
                printf "\033[34mPlaylist: %s\033[0m\n" "$pname"
                printf "\033[38;5;236m────────────────────────────────────────\033[0m\n"
                local sub_options=("Play" "Shuffle" "Add Song" "Remove Song" "Delete Playlist" "Back")
                menu_select "34" "${sub_options[@]}"
                case "$MENU_RESULT" in
                    "Play")
                        PLAYLIST_ACTION="play"
                        PLAYLIST_TARGET="$pname"
                        return
                        ;;
                    "Shuffle")
                        PLAYLIST_ACTION="shuffle"
                        PLAYLIST_TARGET="$pname"
                        return
                        ;;
                    "Add Song")
                        echo ""
                        read -r -e -p $'\001\033[34m\002Search a song to add (leave blank to cancel):\001\033[0m\002 ' add_query
                        if [ -n "$add_query" ]; then
                            if do_interactive_search "$add_query" "$PLAYLIST_DIR/${pname}.txt"; then
                                sleep 1
                            else
                                sleep 1
                            fi
                        fi
                        ;;
                    "Remove Song")
                        PLAYLIST_ACTION="remove"
                        PLAYLIST_TARGET="$pname"
                        return
                        ;;
                    "Delete Playlist")
                        rm -f "$PLAYLIST_DIR/${pname}.txt"
                        echo "Deleted '$pname'."
                        sleep 1
                        break
                        ;;
                    "Back"|*)
                        break
                        ;;
                esac
            done
        fi
    done
}


do_play_playlist() {
    local pname="$1" is_shuffle="$2"
    if [ ! -f "$PLAYLIST_DIR/${pname}.txt" ]; then
        echo "Playlist '$pname' not found."
        return
    fi
    local tracks_count=0
    if [ "$is_shuffle" -eq 1 ]; then
        reader() { shuf "$PLAYLIST_DIR/${pname}.txt"; }
    else
        reader() { cat "$PLAYLIST_DIR/${pname}.txt"; }
    fi
    while read -r line; do
        echo "$line" >> "$QUEUE_FILE"
        tracks_count=$((tracks_count+1))
    done < <(reader)

    local shuffle_txt=""
    if [ "$is_shuffle" -eq 1 ]; then shuffle_txt=" (shuffled)"; fi
    echo "Queued $tracks_count tracks from '$pname'$shuffle_txt."
    sleep 0.5
    playing_mode
}

do_remove_from_playlist() {
    local pname="$1"
    local file="$PLAYLIST_DIR/${pname}.txt"
    if [ ! -f "$file" ]; then
        echo "Playlist '$pname' not found."
        return
    fi
    if [ ! -s "$file" ]; then
        echo "Playlist '$pname' is empty."
        return
    fi

    print_track_table "$file"

    read -r -e -p "Enter numbers to remove (e.g. 1 3 5 or 2-4, or 'cancel'): " choice
    if [ "$choice" == "cancel" ] || [ -z "$choice" ]; then
        echo "Cancelled."
        return
    fi
    local total lines_to_remove=()
    total=$(wc -l < "$file")

    if ! parse_index_selection "$choice" "$total" lines_to_remove; then
        return
    fi

    local removed_count
    removed_count=$(remove_tracks_by_indices "$file" "${lines_to_remove[@]}")
    echo "Removed $removed_count track(s) from '$pname'."
}

if [ $# -gt 0 ]; then
    initial_query="$*"
    echo -e "\033[34mSearching for:\033[0m $initial_query"
    if do_interactive_search "$initial_query"; then
        sleep 0.5
        playing_mode
    fi
fi

PLAYLIST_ACTION=""
PLAYLIST_TARGET=""

while true; do
    clear
    printf "\033[34m              Mstream-CLI\033[0m\n"
    printf "\033[38;5;236m────────────────────────────────────────\033[0m\n"
    menu_select "34" "search" "playlists" "quit"

    case "$MENU_RESULT" in
        "search")
            read -r -e -p $'\001\033[34m\002Search a song (leave blank to cancel):\001\033[0m\002 ' query
            if [ -z "$query" ]; then continue; fi
            if do_interactive_search "$query"; then
                sleep 0.5
                playing_mode
            fi
            ;;
        "playlists")
            do_interactive_playlists
            case "$PLAYLIST_ACTION" in
                "play")    do_play_playlist "$PLAYLIST_TARGET" 0 ;;
                "shuffle") do_play_playlist "$PLAYLIST_TARGET" 1 ;;
                "remove")  do_remove_from_playlist "$PLAYLIST_TARGET" ;;
            esac
            PLAYLIST_ACTION=""
            PLAYLIST_TARGET=""
            ;;
        "quit"|"")
            break
            ;;
    esac
done

echo "Goodbye!"

