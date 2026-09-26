/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "q_shared.h"
#include "dk_save_format.h"

#define HEADER_BYTES 24
#define RECORD_HEADER_BYTES 12
#define FIELD_HEADER_BYTES 8
static const byte magic[8] = {'D', 'K', '3', 'S', 'A', 'V', 'E', 0};

static unsigned int Read32(const byte *data) {
    return (unsigned int)data[0] | ((unsigned int)data[1] << 8) |
           ((unsigned int)data[2] << 16) | ((unsigned int)data[3] << 24);
}

static void Write32(byte *data, unsigned int value) {
    int i;
    for (i = 0; i < 4; ++i) data[i] = (byte)(value >> (8 * i));
}

static unsigned int Checksum(const byte *data, int length) {
    unsigned int crc = ~0u;
    int i, bit;
    for (i = 0; i < length; ++i) {
        crc ^= data[i];
        for (bit = 0; bit < 8; ++bit) crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u)));
    }
    return ~crc;
}

static qboolean WriterError(dkSaveWriter_t *writer, const char *message) {
    if (!*writer->error) Q_strncpyz(writer->error, message, sizeof(writer->error));
    return qfalse;
}

static qboolean ReaderError(dkSaveReader_t *reader, const char *message) {
    if (!*reader->error) Q_strncpyz(reader->error, message, sizeof(reader->error));
    return qfalse;
}

static qboolean NameValid(const char *name) {
    const char *p;
    if (!name || !*name || strlen(name) >= DK_SAVE_NAME) return qfalse;
    for (p = name; *p; ++p) if (!((*p >= 'a' && *p <= 'z') || (*p >= '0' && *p <= '9') || *p == '_')) return qfalse;
    return qtrue;
}

static byte *Reserve(dkSaveWriter_t *writer, int bytes) {
    byte *result;
    if (*writer->error) return NULL;
    if (bytes < 0 || bytes > writer->capacity - writer->length) {
        WriterError(writer, "save exceeds buffer capacity"); return NULL;
    }
    result = writer->data + writer->length;
    memset(result, 0, bytes);
    writer->length += bytes;
    return result;
}

qboolean DK_SaveBegin(dkSaveWriter_t *writer, byte *buffer, int capacity) {
    memset(writer, 0, sizeof(*writer));
    writer->data = buffer; writer->capacity = capacity; writer->recordStart = -1;
    if (!buffer || capacity < HEADER_BYTES || capacity > DK_SAVE_LIMIT) return WriterError(writer, "invalid save buffer");
    Reserve(writer, HEADER_BYTES);
    memcpy(buffer, magic, sizeof(magic));
    Write32(buffer + 8, DK_SAVE_VERSION);
    return qtrue;
}

static void CloseRecord(dkSaveWriter_t *writer) {
    if (writer->recordStart < 0) return;
    Write32(writer->data + writer->recordStart, writer->length - writer->recordStart);
    writer->data[writer->recordStart + 8] = writer->fields & 255;
    writer->data[writer->recordStart + 9] = writer->fields >> 8;
}

qboolean DK_SaveRecord(dkSaveWriter_t *writer, const char *kind, unsigned int id) {
    byte *record;
    int length;
    if (*writer->error) return qfalse;
    if (!NameValid(kind)) return WriterError(writer, "invalid record kind");
    if (writer->records == DK_SAVE_RECORDS) return WriterError(writer, "record limit exceeded");
    CloseRecord(writer);
    length = strlen(kind);
    writer->recordStart = writer->length;
    record = Reserve(writer, RECORD_HEADER_BYTES + length);
    if (!record) return qfalse;
    Write32(record + 4, id);
    record[10] = length;
    memcpy(record + RECORD_HEADER_BYTES, kind, length);
    ++writer->records; writer->fields = 0;
    return qtrue;
}

static byte *Field(dkSaveWriter_t *writer, const char *name, dkSaveType_t type, int count) {
    int bytes, length;
    byte *field;
    if (!NameValid(name)) { WriterError(writer, va("invalid save field name: %.64s", name ? name : "<null>")); return NULL; }
    if (writer->recordStart < 0) { WriterError(writer, "save field has no record"); return NULL; }
    if (count < 0 || count > DK_SAVE_LIMIT / 4 || writer->fields == DK_SAVE_FIELDS) {
        WriterError(writer, "field size or count exceeds limit"); return NULL;
    }
    bytes = type >= DK_SAVE_TEXT ? count : count * 4;
    length = strlen(name);
    field = Reserve(writer, FIELD_HEADER_BYTES + length + bytes);
    if (!field) return NULL;
    field[0] = type; field[1] = length;
    Write32(field + 4, count);
    memcpy(field + FIELD_HEADER_BYTES, name, length);
    ++writer->fields;
    return field + FIELD_HEADER_BYTES + length;
}

qboolean DK_SaveInts(dkSaveWriter_t *writer, const char *name, const int *values, int count) {
    byte *field = Field(writer, name, DK_SAVE_INT, count);
    int i;
    if (!field) return qfalse;
    for (i = 0; i < count; ++i) Write32(field + 4 * i, (unsigned int)values[i]);
    return qtrue;
}

qboolean DK_SaveFloats(dkSaveWriter_t *writer, const char *name, const float *values, int count) {
    byte *field = Field(writer, name, DK_SAVE_FLOAT, count);
    int i;
    if (!field) return qfalse;
    for (i = 0; i < count; ++i) {
        floatint_t value;
        value.f = values[i];
        if ((value.ui & 0x7f800000u) == 0x7f800000u) return WriterError(writer, "non-finite save value");
        Write32(field + 4 * i, value.ui);
    }
    return qtrue;
}

qboolean DK_SaveText(dkSaveWriter_t *writer, const char *name, const char *value) {
    int length = value ? strlen(value) : 0;
    byte *field = Field(writer, name, DK_SAVE_TEXT, length);
    if (!field) return qfalse;
    if (length) memcpy(field, value, length);
    return qtrue;
}

qboolean DK_SaveBytes(dkSaveWriter_t *writer, const char *name, const byte *data, int count) {
    byte *field = Field(writer, name, DK_SAVE_BYTES, count);
    if (!field) return qfalse;
    if (count) memcpy(field, data, count);
    return qtrue;
}

int DK_SaveFinish(dkSaveWriter_t *writer) {
    if (*writer->error) return -1;
    CloseRecord(writer);
    Write32(writer->data + 12, writer->length);
    Write32(writer->data + 16, writer->records);
    Write32(writer->data + 20, Checksum(writer->data + HEADER_BYTES, writer->length - HEADER_BYTES));
    return writer->length;
}

qboolean DK_SaveOpen(dkSaveReader_t *reader, const byte *buffer, int length) {
    memset(reader, 0, sizeof(*reader));
    reader->data = buffer; reader->length = length;
    if (!buffer || length < HEADER_BYTES || length > DK_SAVE_LIMIT) return ReaderError(reader, "invalid save length");
    if (memcmp(buffer, magic, sizeof(magic))) return ReaderError(reader, "not a dk3 save");
    if (Read32(buffer + 8) != DK_SAVE_VERSION) return ReaderError(reader, "unsupported save format version");
    if (Read32(buffer + 12) != length) return ReaderError(reader, "truncated save or trailing bytes");
    if (Read32(buffer + 16) > DK_SAVE_RECORDS) return ReaderError(reader, "record count exceeds limit");
    if (Read32(buffer + 20) != Checksum(buffer + HEADER_BYTES, length - HEADER_BYTES))
        return ReaderError(reader, "save checksum mismatch");
    reader->recordsLeft = Read32(buffer + 16);
    reader->at = reader->recordEnd = HEADER_BYTES;
    return qtrue;
}

qboolean DK_SaveNextRecord(dkSaveReader_t *reader, char kind[DK_SAVE_NAME], unsigned int *id) {
    const byte *record;
    unsigned int size;
    int nameLength;
    if (*reader->error) return qfalse;
    if (reader->fieldsLeft || reader->at != reader->recordEnd) return ReaderError(reader, "record fields were not consumed");
    if (!reader->recordsLeft) {
        if (reader->at != reader->length) return ReaderError(reader, "bytes after final record");
        return qfalse;
    }
    if (reader->length - reader->at < RECORD_HEADER_BYTES) return ReaderError(reader, "truncated record header");
    record = reader->data + reader->at;
    size = Read32(record); nameLength = record[10];
    if (!nameLength || nameLength >= DK_SAVE_NAME || record[11] ||
        size < RECORD_HEADER_BYTES + nameLength || size > reader->length - reader->at)
        return ReaderError(reader, "invalid record length or flags");
    memcpy(kind, record + RECORD_HEADER_BYTES, nameLength); kind[nameLength] = 0;
    if (!NameValid(kind) || strlen(kind) != nameLength) return ReaderError(reader, "invalid record name");
    *id = Read32(record + 4);
    reader->fieldsLeft = record[8] | (record[9] << 8);
    if (reader->fieldsLeft > DK_SAVE_FIELDS) return ReaderError(reader, "field count exceeds limit");
    reader->recordEnd = reader->at + size;
    reader->at += RECORD_HEADER_BYTES + nameLength;
    --reader->recordsLeft;
    return qtrue;
}

qboolean DK_SaveNextField(dkSaveReader_t *reader, dkSaveField_t *field) {
    const byte *header;
    unsigned int count;
    int bytes, nameLength, i;
    if (*reader->error || !reader->fieldsLeft) return qfalse;
    if (reader->recordEnd - reader->at < FIELD_HEADER_BYTES) return ReaderError(reader, "truncated field header");
    header = reader->data + reader->at;
    field->type = header[0]; nameLength = header[1]; count = Read32(header + 4);
    if (header[2] || header[3] || !nameLength || nameLength >= DK_SAVE_NAME || count > DK_SAVE_LIMIT / 4 ||
        field->type < DK_SAVE_INT || field->type > DK_SAVE_BYTES) return ReaderError(reader, "invalid field type, size or flags");
    bytes = field->type >= DK_SAVE_TEXT ? count : count * 4;
    if (FIELD_HEADER_BYTES + nameLength + bytes > reader->recordEnd - reader->at)
        return ReaderError(reader, "truncated field data");
    memcpy(field->name, header + FIELD_HEADER_BYTES, nameLength); field->name[nameLength] = 0;
    if (!NameValid(field->name) || strlen(field->name) != nameLength) return ReaderError(reader, "invalid field name");
    field->data = header + FIELD_HEADER_BYTES + nameLength; field->count = count;
    if (field->type == DK_SAVE_TEXT) {
        if (memchr(field->data, 0, count)) return ReaderError(reader, "embedded NUL in saved text");
    } else if (field->type == DK_SAVE_FLOAT) {
        for (i = 0; i < count; ++i) if ((Read32(field->data + 4 * i) & 0x7f800000u) == 0x7f800000u)
            return ReaderError(reader, "non-finite saved value");
    }
    reader->at += FIELD_HEADER_BYTES + nameLength + bytes;
    --reader->fieldsLeft;
    if (!reader->fieldsLeft && reader->at != reader->recordEnd) return ReaderError(reader, "unaccounted record bytes");
    return qtrue;
}

int DK_SaveInt(const dkSaveField_t *field, int index) {
    if (field->type != DK_SAVE_INT || index < 0 || index >= field->count) Com_Error(ERR_FATAL, "dk3 save: integer accessor mismatch");
    return (int)Read32(field->data + index * 4);
}

float DK_SaveFloat(const dkSaveField_t *field, int index) {
    floatint_t value;
    if (field->type != DK_SAVE_FLOAT || index < 0 || index >= field->count) Com_Error(ERR_FATAL, "dk3 save: float accessor mismatch");
    value.ui = Read32(field->data + index * 4);
    return value.f;
}

qboolean DK_SaveString(const dkSaveField_t *field, char *out, int capacity) {
    if (field->type != DK_SAVE_TEXT || capacity <= field->count) return qfalse;
    memcpy(out, field->data, field->count); out[field->count] = 0;
    return qtrue;
}

qboolean DK_SaveValidate(const byte *buffer, int length, char *error, int capacity) {
    dkSaveReader_t reader;
    dkSaveField_t field;
    static char names[DK_SAVE_FIELDS][DK_SAVE_NAME];
    char kind[DK_SAVE_NAME];
    unsigned int id;
    int fields, i;
    if (DK_SaveOpen(&reader, buffer, length)) {
        while (DK_SaveNextRecord(&reader, kind, &id)) {
            fields = 0;
            while (DK_SaveNextField(&reader, &field)) {
                for (i = 0; i < fields; ++i) if (!strcmp(names[i], field.name)) break;
                if (i < fields) { ReaderError(&reader, "duplicate field name"); break; }
                Q_strncpyz(names[fields++], field.name, DK_SAVE_NAME);
            }
            if (*reader.error) break;
        }
    }
    Q_strncpyz(error, reader.error, capacity);
    return !*reader.error;
}
