# Social preview (OG card) options

Three GitHub social-preview options for the repo. GitHub serves whichever PNG is uploaded under **Settings → General → Social preview**, so this directory is just a holding pen for candidates plus the script that regenerates them.

| File | Layout | Tagline |
|---|---|---|
| `og-card-1.png` | Hero (icon centered, name and tagline below) | "Audio and camera that follow your dock." |
| `og-card-2.png` | Asymmetric (icon left, name and two-line tagline right) | "Plug in. Unplug. / Don't think about it." |
| `og-card-3.png` | Story (USB → speaker → camera, name and tagline below) | "Your laptop knows where it is." |

All three are 1280×640 PNG (GitHub's recommended size) with a 40pt safe margin per [GitHub's published template](https://github.blog/news-insights/social-cards/). Drawing language matches `Sources/AVPainRelieverApp/AppIcon.swift`: pale icy-blue palette, Apple-system-blue glyph, plain native macOS look.

## Upload

1. Pick a PNG from this directory.
2. Repo → **Settings → General → Social preview → Edit → Upload an image**.
3. GitHub serves it on unfurls (Twitter/X, Slack, Discord, etc.) within seconds to a few minutes depending on each platform's cache.

## Regenerate

```sh
swift scripts/generate-og-cards.swift
```

Edits to copy or layout go in `scripts/generate-og-cards.swift` and re-run the same command. The script writes the three PNGs into this directory.
