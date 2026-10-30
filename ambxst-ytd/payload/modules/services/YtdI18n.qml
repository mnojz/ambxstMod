pragma Singleton

import QtQuick
import Quickshell


Singleton {
    id: root

    // Core I18n does not expose a per-mod namespace. Resolve against its
    // language, but keep this mod's strings isolated from upstream catalogs.
    readonly property string language:
        I18n.resolvedLanguage && catalogs[I18n.resolvedLanguage]
            ? I18n.resolvedLanguage : "en"

    readonly property var catalogs: ({
        en: {
            app_name: "Ambxst YTD",
            downloader: "YTD Downloader",
            download_media: "Download media",
            downloading: "Downloading",
            download_failed: "Download failed",
            download_complete: "Download complete",
            download_stopped: "Download stopped",
            audio_mp3: "Audio · MP3",
            video_format: "Video · %1",
            url_placeholder: "Paste or type a YouTube URL",
            paste_from_clipboard: "Paste from clipboard",
            clear_url: "Clear URL",
            download: "Download",
            format: "Format",
            downloads: "Downloads",
            clear_history: "Clear download history",
            stop_download: "Stop download",
            open_folder: "Open download folder",
            remove_from_history: "Remove from history",
            queue_count: "%1 queued",
            downloaded_count: "Downloaded %1 items",
            opener_failed: "Could not open the download folder",
            invalid_url: "Not a valid YouTube or YouTube Music URL",
            playlist_required: "This is a playlist link, choose Whole playlist",
            scope: "Download",
            scope_single: "Single video",
            scope_playlist: "Whole playlist"
        },
        ru: {
            app_name: "Ambxst YTD",
            downloader: "Загрузчик YTD",
            download_media: "Скачать медиа",
            downloading: "Загрузка",
            download_failed: "Ошибка загрузки",
            download_complete: "Загрузка завершена",
            download_stopped: "Загрузка остановлена",
            audio_mp3: "Аудио · MP3",
            video_format: "Видео · %1",
            url_placeholder: "Вставьте ссылку YouTube",
            paste_from_clipboard: "Вставить из буфера",
            clear_url: "Очистить ссылку",
            download: "Скачать",
            format: "Формат",
            downloads: "Загрузки",
            clear_history: "Очистить историю загрузок",
            stop_download: "Остановить загрузку",
            open_folder: "Открыть папку загрузки",
            remove_from_history: "Удалить из истории",
            queue_count: "В очереди: %1",
            downloaded_count: "Загружено элементов: %1",
            opener_failed: "Не удалось открыть папку загрузки",
            invalid_url: "Некорректная ссылка YouTube или YouTube Music",
            playlist_required: "Это ссылка на плейлист, выберите «Весь плейлист»",
            scope: "Скачать",
            scope_single: "Одно видео",
            scope_playlist: "Весь плейлист"
        },
        es: {
            app_name: "Ambxst YTD",
            downloader: "Descargador YTD",
            download_media: "Descargar contenido",
            downloading: "Descargando",
            download_failed: "Error de descarga",
            download_complete: "Descarga completada",
            download_stopped: "Descarga detenida",
            audio_mp3: "Audio · MP3",
            video_format: "Vídeo · %1",
            url_placeholder: "Pega o escribe una URL de YouTube",
            paste_from_clipboard: "Pegar desde el portapapeles",
            clear_url: "Borrar URL",
            download: "Descargar",
            format: "Formato",
            downloads: "Descargas",
            clear_history: "Borrar historial de descargas",
            stop_download: "Detener descarga",
            open_folder: "Abrir carpeta de descarga",
            remove_from_history: "Quitar del historial",
            queue_count: "%1 en cola",
            downloaded_count: "Elementos descargados: %1",
            opener_failed: "No se pudo abrir la carpeta de descarga",
            invalid_url: "URL no válida de YouTube o YouTube Music",
            playlist_required: "Es un enlace de lista, elige «Toda la lista»",
            scope: "Descargar",
            scope_single: "Un vídeo",
            scope_playlist: "Toda la lista"
        }
    })

    function t(key) {
        const selected = catalogs[language] || catalogs.en;
        return selected[key] || catalogs.en[key] || key;
    }
}
