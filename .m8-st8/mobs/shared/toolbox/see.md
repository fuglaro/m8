
* :toolbox::see
* :toolbox::see
  > > Look at an image or PDF file yourself.
  > > Supported: jpg, jpeg, png, gif, webp, bmp, tif, tiff, pdf.
  > > Images are shown as a JPEG with the long side at most 2048px.
  >
  > :shield:workbench
  > :shield:secure contain-reads airgap
  > ```bash records
  > # Convert/copy file into m8-st8/mobs/MOB/.+/.uploads/see-FILE-CALLID.EXT* for uploading, or fail.
  > f=$__file__
  > [ -f "$f" ] || { echo "Not a file: $f" >&2; exit 1; }
  > name=$(basename -- "$f")
  > ext=$(printf %s "${name##*.}" | tr A-Z a-z)
  > mkdir -p "$M8_MOB_DIR/.uploads"
  > part="$M8_MOB_DIR/.uploads/see-${name%.*}-$M8_CALL_ID"
  > case "$ext" in
  >   jpg|jpeg|png|gif|webp|bmp|tif|tiff)
  >     part="$part.jpeg"
  >     ffmpeg -nostdin -loglevel error -y -i "$f" -frames:v 1 -q:v 4 \
  >       -vf "scale='min(2048,iw)':'min(2048,ih)':force_original_aspect_ratio=decrease" \
  >       -f mjpeg "$part" ;;
  >   pdf) part="$part.pdf"; cp -- "$f" "$part" ;;
  >   *) echo "Cannot show .$ext files." >&2
  >      exit 1 ;;
  > esac
  > hash=$(shasum -a 256 -- "$part" | cut -c1-64)
  > printf '* :link::%s\n  > <%s (%s)\n' "$M8_CALL_ID" "$part" "$hash"
  > ```
  > * file string
  >   Path of the image or PDF (relative or absolute).

