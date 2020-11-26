#!/bin/bash -e

dotenv-has() { ! awk -F= -v i="$1" '$1==i{exit(1)}' .env; }
dotenv-set() {
    if dotenv-has "$1"
    then IN="$2" perl -i -pe 's/^('"$1"'=).*/$1.$ENV{IN}/e' .env
    else echo "$1=$2" >>.env
    fi
}
anot() { PREFIX="$1" perl -pe '$_="\x1b[2m$ENV{PREFIX}\x1b[0m$_"'; }
error() { echo -e "\x1b[31mError:\x1b[0m" "$@" >&2; }
dr() { tr -d '\r'; }

FOLDERS=( keys: source-a:lsync-a source-b:lsync-b target:lsync-backup target-replica: )

case "$1" in
setup)
    for d in "${FOLDERS[@]}"; do [ -d "${d%%:*}" ] || mkdir "${d%%:*}" || exit; done

    [ -f keys/client_id_rsa ] && [ -f keys/client_id_rsa.pub ] || \
        ssh-keygen -b "${KEYSIZE:-1024}" -t rsa -f keys/client_id_rsa -N '' -C 'lsyncd-client' | anot 'user-keys> '
    if ! [ -f keys/ssh_host_ecdsa_key.pub ]; then
        echo -e "\x1b[1mGenerating host keys for openssh-server ...\x1b[0m"
        # start docker solargis/openssh-server just for create keys
        docker run --rm -e PUID="$(id -u)" -e PGID="$(id -g)" \
            -v "$PWD"/keys:/config/ssh_host_keys solargis/openssh-server true | anot 'host-keys> '
    fi
    grep -F 'cat keys/client_id_rsa.pub' keys/authorized_keys \
        || echo "command=\"ssh-entrypoint.sh \\\"\${SSH_ORIGINAL_COMMAND:-bash -l}\\\"\" $(cat keys/client_id_rsa.pub)" > keys/authorized_keys
        # || echo "command=\"cd /data; \${SSH_ORIGINAL_COMMAND:-bash -l}\" $(cat keys/client_id_rsa.pub)" > keys/authorized_keys
    chmod 0600 keys/authorized_keys

    [ -f .env ] || touch .env
    dotenv-set PUID "$(id -u)"
    dotenv-set PGID "$(id -g)"
    dotenv-has USER_NAME || dotenv-set USER_NAME "lsync"
    dotenv-has TZ || dotenv-set TZ "Europe/Bratislava"
    dotenv-has SYNC_DELAY || dotenv-set SYNC_DELAY "1"
    [ "${OSTYPE::6}" == darwin ] && dotenv-set INOTIFY_MODE "CloseWrite or Modify"
    dotenv-set HOST_KEY "$(cat keys/ssh_host_ecdsa_key.pub)"
    ;;
check|check-binding)
    for d in "${FOLDERS[@]}"; do
        if ! [ -z "${d#*:}" ]; then
            echo -e "\x1b[1m${d#*:}\x1b[0m"
            printf "\x1b[2m%10s:\x1b[0m %s\n" "${d%%:*}" "$(ls -1A "${d%%:*}" | tr '\n' ' ')"
            printf "\x1b[2m%10s:\x1b[0m %s\n" "container" "$(docker-compose exec "${d#*:}" ls -1A /var/source | dr | tr '\n' ' ')"
        fi
    done
    ;;
start)   "$0" setup && docker-compose build && docker-compose up -d || exit;;
watch)   ( [ "$2" = "just" ] || "$0" start ) && watch -n 1 bash -c "'# containers and bind folers
            docker-compose ps;
            ls -lA source-a source-b target target-replica'";;
stop)    docker-compose down;;
cleanup) "$0" stop && rm -fr keys source-a source-b target target-replica;;
*)       echo "Usage $0 [setup|start|watch [just]|check-binding|stop|cleanup]";;
esac