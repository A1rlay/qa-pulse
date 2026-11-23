# Insignia de estado para READMEs (GET /projects/:slug/badge.svg).
Mime::Type.register "image/svg+xml", :svg unless Mime::Type.lookup_by_extension(:svg)
