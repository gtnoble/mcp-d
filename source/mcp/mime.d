/**
 * MIME type utilities for MCP.
 *
 * This module provides utilities for working with MIME types, including
 * common MIME type constants, MIME type detection, and validation.
 *
 * The module includes:
 * - Common MIME type constants
 * - Functions for guessing MIME types from file extensions
 * - Functions for checking if a MIME type represents text content
 * - Functions for getting file extensions for MIME types
 * - MIME type validation
 */
module mcp.mime;

import std.path : extension;
import std.string : toLower;

/**
 * Common MIME types.
 *
 * This enumeration defines constants for commonly used MIME types,
 * organized by category (text, application, image, audio, video).
 */
enum MimeType {
    // Text
    PLAIN = "text/plain",
    HTML = "text/html",
    CSS = "text/css",
    JAVASCRIPT = "text/javascript",
    MARKDOWN = "text/markdown",
    CSV = "text/csv",
    
    // Application
    JSON = "application/json",
    XML = "application/xml",
    YAML = "application/yaml",
    PDF = "application/pdf",
    ZIP = "application/zip",
    GZIP = "application/gzip",
    OCTET_STREAM = "application/octet-stream",
    
    // Images
    PNG = "image/png",
    JPEG = "image/jpeg",
    GIF = "image/gif",
    SVG = "image/svg+xml",
    ICO = "image/x-icon",
    WEBP = "image/webp",
    
    // Audio
    MP3 = "audio/mpeg",
    WAV = "audio/wav",
    OGG = "audio/ogg",
    
    // Video
    MP4 = "video/mp4",
    WEBM = "video/webm",
    
    // Default
    BINARY = "application/octet-stream"
}

/**
 * Guesses the MIME type based on a file's extension.
 *
 * This function examines the file extension and returns the
 * corresponding MIME type.
 *
 * Params:
 *   path = The file path or name with extension
 *
 * Returns:
 *   The MIME type as a string, or application/octet-stream if unknown
 */
string guessMimeType(string path) {
    auto ext = extension(path).toLower();
    switch (ext) {
        // Text
        case ".txt":  return MimeType.PLAIN;
        case ".html": 
        case ".htm":  return MimeType.HTML;
        case ".css":  return MimeType.CSS;
        case ".js":   return MimeType.JAVASCRIPT;
        case ".md":   
        case ".markdown": return MimeType.MARKDOWN;
        case ".csv":  return MimeType.CSV;
        
        // Application
        case ".json": return MimeType.JSON;
        case ".xml":  return MimeType.XML;
        case ".yaml": 
        case ".yml":  return MimeType.YAML;
        case ".pdf":  return MimeType.PDF;
        case ".zip":  return MimeType.ZIP;
        case ".gz":   return MimeType.GZIP;
        
        // Images
        case ".png":  return MimeType.PNG;
        case ".jpg":
        case ".jpeg": return MimeType.JPEG;
        case ".gif":  return MimeType.GIF;
        case ".svg":  return MimeType.SVG;
        case ".ico":  return MimeType.ICO;
        case ".webp": return MimeType.WEBP;
        
        // Audio
        case ".mp3":  return MimeType.MP3;
        case ".wav":  return MimeType.WAV;
        case ".ogg":  return MimeType.OGG;
        
        // Video
        case ".mp4":  return MimeType.MP4;
        case ".webm": return MimeType.WEBM;
        
        // Default binary
        default:      return MimeType.BINARY;
    }
}

/**
 * Checks if a MIME type represents text content.
 *
 * This function determines whether a MIME type represents textual
 * content that can be read as a string.
 *
 * Params:
 *   mimeType = The MIME type to check
 *
 * Returns:
 *   true if the MIME type represents text content, false otherwise
 */
bool isTextMimeType(string mimeType) {
    import std.algorithm : startsWith, canFind;
    
    // Text types
    if (mimeType.startsWith("text/"))
        return true;
        
    // Known text-based application types
    const textBasedTypes = [
        MimeType.JSON,
        MimeType.XML,
        MimeType.YAML,
        "application/javascript",
        "application/ecmascript",
        "application/x-httpd-php",
        "application/x-sh"
    ];
    
    return textBasedTypes.canFind(mimeType);
}

/**
 * Gets the file extension for a MIME type.
 *
 * This function returns the standard file extension associated
 * with a given MIME type.
 *
 * Params:
 *   mimeType = The MIME type
 *
 * Returns:
 *   The file extension (including the dot) for the MIME type
 */
string getExtensionForMimeType(string mimeType) {
    switch (mimeType) {
        // Text
        case MimeType.PLAIN: return ".txt";
        case MimeType.HTML:  return ".html";
        case MimeType.CSS:   return ".css";
        case MimeType.JAVASCRIPT: return ".js";
        case MimeType.MARKDOWN: return ".md";
        case MimeType.CSV:   return ".csv";
        
        // Application
        case MimeType.JSON:  return ".json";
        case MimeType.XML:   return ".xml";
        case MimeType.YAML:  return ".yaml";
        case MimeType.PDF:   return ".pdf";
        case MimeType.ZIP:   return ".zip";
        case MimeType.GZIP:  return ".gz";
        
        // Images
        case MimeType.PNG:   return ".png";
        case MimeType.JPEG:  return ".jpg";
        case MimeType.GIF:   return ".gif";
        case MimeType.SVG:   return ".svg";
        case MimeType.ICO:   return ".ico";
        case MimeType.WEBP:  return ".webp";
        
        // Audio
        case MimeType.MP3:   return ".mp3";
        case MimeType.WAV:   return ".wav";
        case MimeType.OGG:   return ".ogg";
        
        // Video
        case MimeType.MP4:   return ".mp4";
        case MimeType.WEBM:  return ".webm";
        
        // Default binary
        default: return ".bin";
    }
}

/**
 * Validates a MIME type string.
 *
 * This function checks if a string is a valid MIME type according
 * to the basic format rules (type/subtype).
 *
 * Params:
 *   mimeType = The MIME type string to validate
 *
 * Returns:
 *   true if the MIME type is valid, false otherwise
 */
bool isValidMimeType(string mimeType) {
    import std.regex : matchFirst, regex;
    
    // Basic MIME type format: type/subtype
    auto pattern = regex(`^[a-zA-Z0-9][a-zA-Z0-9!#$&^_-]{0,126}/[a-zA-Z0-9][a-zA-Z0-9!#$&^_-]{0,126}$`);
    return !matchFirst(mimeType, pattern).empty;
}
