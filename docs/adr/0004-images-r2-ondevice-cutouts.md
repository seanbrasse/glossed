# 0004. Images: on-device cutouts, R2 storage, ingest-time catalog processing

Date: 2026-08-27 | Status: accepted (PRD §08)

## Context
The shelf is the user's actual bottles, background removed — the emotional core. Per-image removal services would cost ~$36k across the catalog; server GPUs violate the run rate. R2 has zero egress and a free tier covering years of cutouts (~150KB each).

## Decision
User photos: Vision foreground-instance-mask **on device** → EXIF-stripped cutout → presigned PUT to R2 under non-guessable per-user keys. Catalog images: fetched and processed **once at ingest** (normalize → batch rembg/Vision on our own Mac → derivatives → R2); hotlinking only as fallback. Cutouts scale by real product dimensions (variant size data) on a shared ground line. Fallback chain: user photo → catalog image → typographic tile.

## Consequences
Easy: zero per-image cost, privacy win (background gone = bathroom gone), differentiated shelf rendering. Hard: consistency work (angle outliers, hand-check top 200), device-only testing for the mask API. Revisit if: R2 pricing changes or mask quality on dark/transparent packaging needs a fallback model.
