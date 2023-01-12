#!/bin/sh

UPSTREAM="https://github.com/vcheckzen/KeepAliveE5.git"
BOT_USER="github-actions[bot]"
BOT_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"
CONFIG_PATH="config"

exit_on_error() {
    min_secs="$1"
    max_time="$2"
    cmd="$3"

    start=$(date +%s)
    # https://man7.org/linux/man-pages/man1/timeout.1.html
    # https://stackoverflow.com/questions/29936956/linux-how-does-the-kill-k-switch-work-in-timeout-command
    # https://stackoverflow.com/questions/42615374/the-linux-timeout-command-and-exit-codes
    # do not quote $cmd
    # shellcheck disable=SC2086
    # output="$(2>&1 timeout -s KILL "$max_time" $cmd)"
    output="$(timeout --preserve-status -k 1m "$max_time" $cmd 2>&1)"
    ret=$?
    end=$(date +%s)
    echo "$output"

    [ $ret -ne 0 ] && exit 1
    [ $((end - start)) -lt "$min_secs" ] && exit 1
    # https://man7.org/linux/man-pages/man1/grep.1.html
    # https://unix.stackexchange.com/questions/305547/broken-pipe-when-grepping-output-but-only-with-i-flag
    echo "$output" | grep '成功' >/dev/null || exit 1
    echo "$output" | grep -iE '错误|失败|error|except' >/dev/null && exit 1

    return 0
}

register() {
    (
        cd register || exit 1
        exit_on_error "90" "5m" "bash register_apps_by_force.sh"
    )
    ret=$?

    [ "$(ls -A "$CONFIG_PATH" 2>/dev/null)" ] &&
        poetry run python crypto.py e || exit 1

    exit $ret
}

invoke() {
    [ -d "$CONFIG_PATH" ] || {
        echo "没有找到配置文件, 请执行应用注册 Action."
        exit 1
    }

    # sleep $((RANDOM % 127))
    poetry run python crypto.py d || exit 1
    (
        exit_on_error "25" "5m" "poetry run python task.py"
    )
    ret=$?
    poetry run python crypto.py e || exit 1
    exit $ret
}

sync() {
    action="$1"
    message="$2"

    # call windows git from wsl
    git=git
    command -v git.exe 1>/dev/null && git=git.exe

    $git config user.name "$BOT_USER"
    $git config user.email "$BOT_EMAIL"

    [ "$action" = "pull" ] && {
        [ -d "$CONFIG_PATH" ] && {
            tmp_path="/tmp/$(cat /proc/sys/kernel/random/uuid)"
            mkdir -p "$tmp_path"
            mv "$CONFIG_PATH" "$tmp_path"
        }

        $git remote add upstream "$UPSTREAM"
        $git pull upstream master 1>/dev/null 2>&1
        $git reset --hard upstream/master

        [ -z ${tmp_path+x} ] || {
            mv "$tmp_path"/* ./
            rm -rf "$tmp_path"
        }

        exit 0
    }

    $git checkout --orphan latest_branch
    $git rm -rf --cached .
    $git add -A
    $git commit -m "$message"
    $git branch -D master
    $git branch -m master
    $git push -f origin master
}

case $1 in
register)
    register
    ;;
invoke)
    invoke
    ;;
pull | push)
    sync "$@"
    ;;
*)
    exit 0
    ;;
esac
