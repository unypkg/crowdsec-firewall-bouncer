#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091,SC2154,SC1003,SC2005,SC2016

current_dir="$(pwd)"
unypkg_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
unypkg_root_dir="$(cd -- "$unypkg_script_dir"/.. &>/dev/null && pwd)"

cd "$unypkg_root_dir" || exit

#############################################################################################
### Start of script

function check_firewall {
    # Default firewall backend is nftables
    FW_BACKEND="nftables"

    iptables="true"
    if command -v iptables >/dev/null; then
        FW_BACKEND="iptables"
        echo "iptables found"
    else
        echo "iptables not found"
        iptables="false"
    fi

    nftables="true"
    if command -v nft >/dev/null; then
        FW_BACKEND="nftables"
        echo "nftables found"
    else
        echo "nftables not found"
        nftables="false"
    fi

    if [ "$nftables" = "false" ] && [ "$iptables" = "false" ]; then
        echo "No firewall found, please install nftables or iptables and install this package again."
    fi

    if [ "$nftables" = "true" ] && [ "$iptables" = "true" ]; then
        echo "Found nftables (default) and iptables. Using nftables, you may uninstall iptables."
        FW_BACKEND="nftables"
    fi
}

BOUNCER_NAME="crowdsec-firewall-bouncer"
CONFIG_DIR="/etc/uny/crowdsec/bouncers"
SERVICE="$BOUNCER_NAME.service"
SYSTEMD_PATH_FILE="/etc/systemd/system/uny-$SERVICE"
CSCLI_BIN=(/uny/pkg/crowdsec/*/bin/cscli)

[[ -d ${CONFIG_DIR} ]] || mkdir -pv ${CONFIG_DIR}
if [[ ! -s ${CONFIG_DIR}/${BOUNCER_NAME}.yaml ]]; then
    install -D -m 0600 config/"$BOUNCER_NAME".yaml "$CONFIG_DIR"/"$BOUNCER_NAME".yaml

    if command -v "${CSCLI_BIN[0]}" >/dev/null; then
        echo "cscli found, generating bouncer api key."
        bouncer_id="$BOUNCER_NAME-$(date +%s)"
        API_KEY=$("${CSCLI_BIN[0]}" -oraw bouncers add "$bouncer_id")
        echo "$bouncer_id" >"$CONFIG_DIR"/"$BOUNCER_NAME".id
        echo "API Key: $API_KEY"
        READY="yes"
    else
        echo "cscli not found, you will need to generate an api key."
        READY="no"
    fi

    check_firewall
    # shellcheck disable=SC2016
    API_KEY=${API_KEY} BACKEND=${FW_BACKEND} envsubst '$API_KEY $BACKEND' <config/"$BOUNCER_NAME".yaml |
        install -D -m 0600 /dev/stdin "$CONFIG_DIR"/"$BOUNCER_NAME".yaml
fi

sed -r "s|=/bin/(.*)|=/usr/bin/env bash -c \"\1\"|" -i config/crowdsec.service
CFG=${CONFIG_DIR} BIN="$unypkg_root_dir/bin/$BOUNCER_NAME" envsubst '$CFG $BIN' <"config/$SERVICE" >"$SYSTEMD_PATH_FILE"
#sed "s|.*Alias=.*||g" -i /etc/systemd/system/uny-mariadb.service
sed -e '/\[Install\]/a\' -e "Alias=$SERVICE" -i "$SYSTEMD_PATH_FILE"
systemctl daemon-reload

#############################################################################################
### End of script

cd "$current_dir" || exit
