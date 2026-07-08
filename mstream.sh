#!/bin/bash

# configuration
CONFIG_DIR="$HOME/.mstream"
PLAYLIST_DIR="$CONFIG_DIR/playlists"
QUEUE_FILE="$CONFIG_DIR/queue.txt"
PID_FILE="$CONFIG_DIR/mpv.pid"

mkdir -p "$PLAYLIST_DIR"
> "$QUEUE_FILE"
rm -f "$PID_FILE"

# check dependencies
if ! command -v mpv &> /dev/null; then
    echo -e "\033[1;31mError: mpv is not installed.\033[0m"
    exit 1
fi

if ! command -v yt-dlp &> /dev/null; then
    echo -e "\033[1;31mError: yt-dlp is not installed. Please install it globally (e.g. pipx install yt-dlp).\033[0m"
    exit 1
fi

# cleanup on exit
cleanup() {
    if [ -n "$WORKER_PID" ]; then
        kill $WORKER_PID 2>/dev/null
    fi
    if [ -f "$PID_FILE" ]; then
        kill -9 $(cat "$PID_FILE") 2>/dev/null
    fi
    kill $(jobs -p) 2>/dev/null
    rm -f "$PID_FILE" "$QUEUE_FILE"
    exit 0
}
trap cleanup EXIT INT TERM HUP

is_paused=0

# background worker
player_worker() {
    while true; do
        if [ -s "$QUEUE_FILE" ]; then
            line=$(head -n 1 "$QUEUE_FILE")
            sed -i.bak '1d' "$QUEUE_FILE" && rm -f "${QUEUE_FILE}.bak"
            
            IFS='|' read -r vid title artist <<< "$line"
            if [ -n "$vid" ]; then
                echo -e "\n\033[1;32m▶ Now Playing:\033[0m \033[1;37m$title\033[0m by \033[3m$artist\033[0m"
                echo -ne "mstream> "
                
                url="https://music.youtube.com/watch?v=$vid"
                mpv --no-video --ytdl-format=bestaudio "$url" > /dev/null 2>&1 &
                MPV_PID=$!
                echo $MPV_PID > "$PID_FILE"
                wait $MPV_PID
                status=$?
                rm -f "$PID_FILE"
                is_paused=0
                
                # check for errors (4 = quit/skip, 143 = killed, 137 = force quit)
                if [ $status -ne 0 ] && [ $status -ne 4 ] && [ $status -ne 143 ] && [ $status -ne 137 ]; then
                    echo -e "\n\033[1;31m⚠ Error: Failed to stream '$title'. (It may be age-restricted or blocked)\033[0m"
                    echo -ne "mstream> "
                fi
                
                # prevent youtube 403 rate-limiting
                if [ $status -eq 4 ] || [ $status -eq 143 ] || [ $status -eq 137 ] || [ $status -ne 0 ]; then
                    sleep 1.5
                fi
            fi
        else
            sleep 0.5
        fi
    done
}

# start worker in background
player_worker &
WORKER_PID=$!

search_song() {
    local query="$1"
    local limit="${2:-1}"
    # reject URLs — only song name queries are allowed
    if [[ "$query" =~ ://|^www\. ]]; then
        echo -e "\033[1;31m✘ Links are not supported. Please search by song name instead.\033[0m" >&2
        return
    fi
    echo -e "\033[36mSearching...\033[0m" >&2
    # encode query for URL
    local encoded_query=$(python3 -c "import urllib.parse; print(urllib.parse.quote_plus('$query'))")
    local search_url="https://music.youtube.com/search?q=${encoded_query}"
    local raw_output=$(yt-dlp --print "%(id)s|%(title)s|%(artist)s" "$search_url" --playlist-items "1:${limit}" --skip-download 2>/dev/null)
    
    if [ -n "$raw_output" ]; then
        echo "$raw_output"
    fi
}

show_help() {
    echo -e "\033[1;36mCommands:\033[0m"
    echo "  play <query>         Search and queue a song"
    echo "  search <query>       Interactively search and queue"
    echo "  pause / resume       Control playback"
    echo "  skip                 Skip current track"
    echo "  queue                View the current queue"
    echo "  dequeue              Remove songs from the queue"
    echo "  move <from> <to>     Move a song in the queue"
    echo "  clear                Clear the queue"
    echo "  add <plist> <query>  Add song to a playlist"
    echo "  remove <plist>       Remove a song from a playlist"
    echo "  list                 List your playlists"
    echo "  playlist <name>      Queue an entire playlist"
    echo "  quit                 Exit"
}

echo -e "\033[1;36mWelcome to mstream!\033[0m"
show_help

# handle initial command arguments
if [ $# -gt 0 ]; then
    initial_cmd="$*"
else
    initial_cmd=""
fi

# main interactive loop
while true; do
    if [ -n "$initial_cmd" ]; then
        input="$initial_cmd"
        initial_cmd=""
        echo -e "mstream> $input"
    else
        read -e -p "mstream> " input
    fi
    
    # parse input preserving quotes
    eval set -- $input 2>/dev/null
    cmd="$1"
    shift
    args="$*"
    
    case "$cmd" in
        "play")
            if [ -z "$args" ]; then
                echo -e "\033[1;31mUsage: play <query>\033[0m"
                continue
            fi
            res=$(search_song "$args" 1)
            if [ -n "$res" ]; then
                echo "$res" >> "$QUEUE_FILE"
                IFS='|' read -r vid title artist <<< "$res"
                echo -e "\033[1;35mQueued:\033[0m $title by $artist"
            else
                echo -e "\033[1;33mNo results found.\033[0m"
            fi
            ;;
        "search")
            if [ -z "$args" ]; then
                echo -e "\033[1;31mUsage: search <query>\033[0m"
                continue
            fi
            results=$(search_song "$args" 5)
            if [ -z "$results" ]; then
                echo -e "\033[1;33mNo results found.\033[0m"
                continue
            fi
            
            echo -e "\n\033[1;36m#   Title                               Artist\033[0m"
            echo "------------------------------------------------------"
            i=1
            declare -A res_array
            while IFS='|' read -r vid title artist; do
                res_array[$i]="$vid|$title|$artist"
                printf "%-3s %-35s %s\n" "$i" "${title:0:34}" "$artist"
                i=$((i+1))
            done <<< "$results"
            
            read -e -p "Enter a number to queue: " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ -n "${res_array[$choice]}" ]; then
                echo "${res_array[$choice]}" >> "$QUEUE_FILE"
                IFS='|' read -r vid title artist <<< "${res_array[$choice]}"
                echo -e "\033[1;35mQueued:\033[0m $title by $artist"
            else
                echo -e "\033[1;31mInvalid choice.\033[0m"
            fi
            ;;
        "pause")
            if [ -f "$PID_FILE" ] && [ "$is_paused" -eq 0 ]; then
                kill -STOP $(cat "$PID_FILE")
                is_paused=1
                echo -e "\033[1;33m⏸ Paused\033[0m"
            else
                echo "Not playing or already paused."
            fi
            ;;
        "resume")
            if [ -f "$PID_FILE" ] && [ "$is_paused" -eq 1 ]; then
                kill -CONT $(cat "$PID_FILE")
                is_paused=0
                echo -e "\033[1;32m▶ Resumed\033[0m"
            else
                echo "Not paused."
            fi
            ;;
        "skip")
            if [ -f "$PID_FILE" ]; then
                kill -TERM $(cat "$PID_FILE") 2>/dev/null
                echo -e "\033[1;35m⏭ Skipped\033[0m"
            else
                echo "Nothing is playing."
            fi
            ;;
        "clear")
            > "$QUEUE_FILE"
            echo -e "\033[1;35mQueue cleared.\033[0m"
            ;;
        "queue")
            if [ ! -s "$QUEUE_FILE" ]; then
                echo -e "\033[1;33mQueue is empty.\033[0m"
                continue
            fi
            echo -e "\n\033[1;36m#   Title                               Artist\033[0m"
            echo "------------------------------------------------------"
            i=1
            while IFS='|' read -r vid title artist; do
                printf "%-3s %-35s %s\n" "$i" "${title:0:34}" "$artist"
                i=$((i+1))
            done < "$QUEUE_FILE"
            ;;
        "dequeue")
            if [ ! -s "$QUEUE_FILE" ]; then
                echo -e "\033[1;33mQueue is empty.\033[0m"
                continue
            fi
            echo -e "\n\033[1;36m#   Title                               Artist\033[0m"
            echo "------------------------------------------------------"
            i=1
            while IFS='|' read -r vid title artist; do
                printf "%-3s %-35s %s\n" "$i" "${title:0:34}" "$artist"
                i=$((i+1))
            done < "$QUEUE_FILE"
            
            read -e -p "Enter numbers to remove (e.g. 1 3 5 or 2-4, or 'cancel'): " choice
            if [ "$choice" == "cancel" ]; then
                echo "Cancelled."
                continue
            fi
            total=$(wc -l < "$QUEUE_FILE")
            
            lines_to_remove=()
            valid=1
            for token in $choice; do
                if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                    start=${BASH_REMATCH[1]}
                    end=${BASH_REMATCH[2]}
                    if [ "$start" -ge 1 ] && [ "$end" -le "$total" ] && [ "$start" -le "$end" ]; then
                        for ((n=start; n<=end; n++)); do
                            lines_to_remove+=("$n")
                        done
                    else
                        echo -e "\033[1;31mInvalid range: $token\033[0m"
                        valid=0
                        break
                    fi
                elif [[ "$token" =~ ^[0-9]+$ ]] && [ "$token" -ge 1 ] && [ "$token" -le "$total" ]; then
                    lines_to_remove+=("$token")
                else
                    echo -e "\033[1;31mInvalid input: $token\033[0m"
                    valid=0
                    break
                fi
            done
            
            if [ "$valid" -eq 0 ] || [ ${#lines_to_remove[@]} -eq 0 ]; then
                continue
            fi
            
            sorted=($(printf '%s\n' "${lines_to_remove[@]}" | sort -rnu))
            removed_count=0
            for ln in "${sorted[@]}"; do
                removed=$(sed -n "${ln}p" "$QUEUE_FILE")
                IFS='|' read -r vid title artist <<< "$removed"
                sed -i.bak "${ln}d" "$QUEUE_FILE" && rm -f "${QUEUE_FILE}.bak"
                echo -e "\033[1;32m✔ Removed '$title'\033[0m"
                removed_count=$((removed_count+1))
            done
            echo -e "\033[1;35mRemoved $removed_count track(s) from queue.\033[0m"
            ;;
        "move")
            if [ ! -s "$QUEUE_FILE" ]; then
                echo -e "\033[1;33mQueue is empty.\033[0m"
                continue
            fi
            from_pos="$1"
            to_pos="$2"
            total=$(wc -l < "$QUEUE_FILE")
            if [ -z "$from_pos" ] || [ -z "$to_pos" ]; then
                echo -e "\n\033[1;36m#   Title                               Artist\033[0m"
                echo "------------------------------------------------------"
                i=1
                while IFS='|' read -r vid title artist; do
                    printf "%-3s %-35s %s\n" "$i" "${title:0:34}" "$artist"
                    i=$((i+1))
                done < "$QUEUE_FILE"
                echo -e "\033[1;31mUsage: move <from> <to>\033[0m"
                continue
            fi
            if ! [[ "$from_pos" =~ ^[0-9]+$ ]] || ! [[ "$to_pos" =~ ^[0-9]+$ ]] || \
               [ "$from_pos" -lt 1 ] || [ "$from_pos" -gt "$total" ] || \
               [ "$to_pos" -lt 1 ] || [ "$to_pos" -gt "$total" ]; then
                echo -e "\033[1;31mInvalid positions. Must be between 1 and $total.\033[0m"
                continue
            fi
            if [ "$from_pos" -eq "$to_pos" ]; then
                echo "Already at that position."
                continue
            fi
            # extract the line, delete it, then insert at new position
            line=$(sed -n "${from_pos}p" "$QUEUE_FILE")
            sed -i.bak "${from_pos}d" "$QUEUE_FILE" && rm -f "${QUEUE_FILE}.bak"
            sed -i.bak "${to_pos}i\\${line}" "$QUEUE_FILE" && rm -f "${QUEUE_FILE}.bak"
            IFS='|' read -r vid title artist <<< "$line"
            echo -e "\033[1;32m✔ Moved '$title' from #$from_pos → #$to_pos\033[0m"
            ;;
        "add")
            pname="$1"
            shift
            pquery="$*"
            if [ -z "$pname" ] || [ -z "$pquery" ]; then
                echo -e "\033[1;31mUsage: add <playlist_name> <query>\033[0m"
                continue
            fi
            res=$(search_song "$pquery" 1)
            if [ -n "$res" ]; then
                echo "$res" >> "$PLAYLIST_DIR/${pname}.txt"
                IFS='|' read -r vid title artist <<< "$res"
                echo -e "\033[1;32m✔ Added '$title' to playlist '$pname'.\033[0m"
            else
                echo -e "\033[1;33mNo results found.\033[0m"
            fi
            ;;
        "list")
            echo -e "\033[1;35mLocal Playlists:\033[0m"
            count=0
            for f in "$PLAYLIST_DIR"/*.txt; do
                if [ -f "$f" ]; then
                    pname=$(basename "$f" .txt)
                    tracks=$(wc -l < "$f")
                    echo "$pname ($tracks tracks)"
                    count=$((count+1))
                fi
            done
            if [ "$count" -eq 0 ]; then
                echo -e "\033[33mNo playlists found.\033[0m"
            fi
            ;;
        "remove")
            pname="$1"
            if [ -z "$pname" ]; then
                echo -e "\033[1;31mUsage: remove <playlist_name>\033[0m"
                continue
            fi
            if [ ! -f "$PLAYLIST_DIR/${pname}.txt" ]; then
                echo -e "\033[1;31mPlaylist '$pname' not found.\033[0m"
                continue
            fi
            if [ ! -s "$PLAYLIST_DIR/${pname}.txt" ]; then
                echo -e "\033[1;33mPlaylist '$pname' is empty.\033[0m"
                continue
            fi
            
            echo -e "\n\033[1;36m#   Title                               Artist\033[0m"
            echo "------------------------------------------------------"
            i=1
            while IFS='|' read -r vid title artist; do
                printf "%-3s %-35s %s\n" "$i" "${title:0:34}" "$artist"
                i=$((i+1))
            done < "$PLAYLIST_DIR/${pname}.txt"
            
            read -e -p "Enter numbers to remove (e.g. 1 3 5 or 2-4, or 'cancel'): " choice
            if [ "$choice" == "cancel" ]; then
                echo "Cancelled."
                continue
            fi
            total=$(wc -l < "$PLAYLIST_DIR/${pname}.txt")
            
            # expand ranges (e.g. 2-4 -> 2 3 4) and collect all numbers
            lines_to_remove=()
            valid=1
            for token in $choice; do
                if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                    start=${BASH_REMATCH[1]}
                    end=${BASH_REMATCH[2]}
                    if [ "$start" -ge 1 ] && [ "$end" -le "$total" ] && [ "$start" -le "$end" ]; then
                        for ((n=start; n<=end; n++)); do
                            lines_to_remove+=("$n")
                        done
                    else
                        echo -e "\033[1;31mInvalid range: $token\033[0m"
                        valid=0
                        break
                    fi
                elif [[ "$token" =~ ^[0-9]+$ ]] && [ "$token" -ge 1 ] && [ "$token" -le "$total" ]; then
                    lines_to_remove+=("$token")
                else
                    echo -e "\033[1;31mInvalid input: $token\033[0m"
                    valid=0
                    break
                fi
            done
            
            if [ "$valid" -eq 0 ] || [ ${#lines_to_remove[@]} -eq 0 ]; then
                continue
            fi
            
            # deduplicate and sort in reverse so deletions don't shift line numbers
            sorted=($(printf '%s\n' "${lines_to_remove[@]}" | sort -rnu))
            removed_count=0
            for ln in "${sorted[@]}"; do
                removed=$(sed -n "${ln}p" "$PLAYLIST_DIR/${pname}.txt")
                IFS='|' read -r vid title artist <<< "$removed"
                sed -i.bak "${ln}d" "$PLAYLIST_DIR/${pname}.txt" && rm -f "$PLAYLIST_DIR/${pname}.txt.bak"
                echo -e "\033[1;32m✔ Removed '$title'\033[0m"
                removed_count=$((removed_count+1))
            done
            echo -e "\033[1;35mRemoved $removed_count track(s) from '$pname'.\033[0m"
            ;;
        "playlist")
            pname="$1"
            shift
            is_shuffle=0
            if [ "$1" == "shuffle" ]; then
                is_shuffle=1
            fi
            if [ -z "$pname" ]; then
                echo -e "\033[1;31mUsage: playlist <name> [shuffle]\033[0m"
                continue
            fi
            if [ -f "$PLAYLIST_DIR/${pname}.txt" ]; then
                tracks_count=0
                if [ "$is_shuffle" -eq 1 ]; then
                    list_cmd="shuf \"$PLAYLIST_DIR/${pname}.txt\""
                else
                    list_cmd="cat \"$PLAYLIST_DIR/${pname}.txt\""
                fi
                while read -r line; do
                    echo "$line" >> "$QUEUE_FILE"
                    tracks_count=$((tracks_count+1))
                done < <(eval "$list_cmd")
                
                shuffle_txt=""
                if [ "$is_shuffle" -eq 1 ]; then shuffle_txt=" (shuffled)"; fi
                echo -e "\033[1;35mQueued $tracks_count tracks from '$pname'$shuffle_txt.\033[0m"
            else
                echo -e "\033[1;31mPlaylist '$pname' not found.\033[0m"
            fi
            ;;
        "help"|"?")
            show_help
            ;;
        "quit"|"exit")
            break
            ;;
        "")
            ;;
        *)
            echo -e "\033[1;31mUnknown command: $cmd\033[0m"
            ;;
    esac
done

echo "Goodbye!"
