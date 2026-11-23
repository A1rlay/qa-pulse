# Pin npm packages by running ./bin/importmap

pin "application"
# Chart.js 4.4.1, build UMD oficial (npm, sha1 verificado) descargado en vendor/javascript:
# la demo no depende de un CDN. Define window.Chart con todos los tipos de gráfica registrados.
pin "chart.umd", to: "chart.umd.js" # @4.4.1
pin_all_from "app/javascript/qa", under: "qa"
