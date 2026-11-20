// Ghostty draws a lock icon as the cursor while a password prompt is active
// (sudo, ssh, etc.). This paints over that cell with the background, so the
// prompt looks like a plain, empty hidden input. Other cursors are untouched.
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 color = texture(iChannel0, uv);

    // Cursor style 4 = lock (password input).
    if (abs(iCurrentCursorStyle.x - 4.0) < 0.5) {
        float x0 = iCurrentCursor.x - 1.0;
        float x1 = iCurrentCursor.x + iCurrentCursor.z + 1.0;
        float yTop = iCurrentCursor.y + 1.0;
        float yBot = iCurrentCursor.y - iCurrentCursor.w - 1.0;
        if (fragCoord.x >= x0 && fragCoord.x <= x1 &&
            fragCoord.y >= yBot && fragCoord.y <= yTop) {
            // Borrow the empty cell to the right so transparency matches.
            vec2 probe = vec2(x1 + iCurrentCursor.z * 0.5, fragCoord.y) / iResolution.xy;
            fragColor = texture(iChannel0, probe);
            return;
        }
    }
    fragColor = color;
}
