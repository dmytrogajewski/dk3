/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Test-only reference: retain upstream code and license in its original file. */
#define MSG_BeginReading Ref_MSG_BeginReading
#define MSG_BeginReadingOOB Ref_MSG_BeginReadingOOB
#define MSG_Bitstream Ref_MSG_Bitstream
#define MSG_Clear Ref_MSG_Clear
#define MSG_Copy Ref_MSG_Copy
#define MSG_Dkq3ChangeVector Ref_MSG_Dkq3ChangeVector
#define MSG_HashKey Ref_MSG_HashKey
#define MSG_Init Ref_MSG_Init
#define MSG_InitOOB Ref_MSG_InitOOB
#define MSG_LookaheadByte Ref_MSG_LookaheadByte
#define MSG_NUinitHuffman Ref_MSG_NUinitHuffman
#define MSG_ReadAngle16 Ref_MSG_ReadAngle16
#define MSG_ReadBigString Ref_MSG_ReadBigString
#define MSG_ReadBits Ref_MSG_ReadBits
#define MSG_ReadByte Ref_MSG_ReadByte
#define MSG_ReadChar Ref_MSG_ReadChar
#define MSG_ReadData Ref_MSG_ReadData
#define MSG_ReadDeltaEntity Ref_MSG_ReadDeltaEntity
#define MSG_ReadDeltaEntityDkq3 Ref_MSG_ReadDeltaEntityDkq3
#define MSG_ReadDeltaKey Ref_MSG_ReadDeltaKey
#define MSG_ReadDeltaKeyFloat Ref_MSG_ReadDeltaKeyFloat
#define MSG_ReadDeltaPlayerstate Ref_MSG_ReadDeltaPlayerstate
#define MSG_ReadDeltaUsercmdKey Ref_MSG_ReadDeltaUsercmdKey
#define MSG_ReadFloat Ref_MSG_ReadFloat
#define MSG_ReadLong Ref_MSG_ReadLong
#define MSG_ReadShort Ref_MSG_ReadShort
#define MSG_ReadString Ref_MSG_ReadString
#define MSG_ReadStringLine Ref_MSG_ReadStringLine
#define MSG_ReportChangeVectors_f Ref_MSG_ReportChangeVectors_f
#define MSG_WriteAngle Ref_MSG_WriteAngle
#define MSG_WriteAngle16 Ref_MSG_WriteAngle16
#define MSG_WriteBigString Ref_MSG_WriteBigString
#define MSG_WriteBits Ref_MSG_WriteBits
#define MSG_WriteByte Ref_MSG_WriteByte
#define MSG_WriteChar Ref_MSG_WriteChar
#define MSG_WriteData Ref_MSG_WriteData
#define MSG_WriteDeltaEntity Ref_MSG_WriteDeltaEntity
#define MSG_WriteDeltaEntityDkq3 Ref_MSG_WriteDeltaEntityDkq3
#define MSG_WriteDeltaKey Ref_MSG_WriteDeltaKey
#define MSG_WriteDeltaKeyFloat Ref_MSG_WriteDeltaKeyFloat
#define MSG_WriteDeltaPlayerstate Ref_MSG_WriteDeltaPlayerstate
#define MSG_WriteDeltaUsercmdKey Ref_MSG_WriteDeltaUsercmdKey
#define MSG_WriteFloat Ref_MSG_WriteFloat
#define MSG_WriteLong Ref_MSG_WriteLong
#define MSG_WriteShort Ref_MSG_WriteShort
#define MSG_WriteString Ref_MSG_WriteString
#define MSG_initHuffman Ref_MSG_initHuffman
#include "../../engine/ioquake3/code/qcommon/msg.c"

/* Engine services used by the isolated codec test executable. */
cvar_t *cl_shownet;
void QDECL Com_Printf(const char *format, ...) { (void)format; }
void QDECL Com_Error(int code, const char *format, ...) {
    va_list args; (void)code;
    va_start(args, format); vfprintf(stderr, format, args); va_end(args);
    abort();
}
void Q_strncpyz(char *dest, const char *src, int size) {
    if (size < 1) abort();
    strncpy(dest, src, size-1); dest[size-1]=0;
}
