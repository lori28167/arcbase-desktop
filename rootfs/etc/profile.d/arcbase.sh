# Arcbase Desktop — ambiente comune
# Le app Debian esportate da `arc` vivono in /usr/local (bin, applications, icons)
case ":${XDG_DATA_DIRS-}:" in
    *:/usr/local/share:*) ;;
    *) export XDG_DATA_DIRS="/usr/local/share:${XDG_DATA_DIRS:-/usr/share}" ;;
esac
export EDITOR=${EDITOR:-vim}
