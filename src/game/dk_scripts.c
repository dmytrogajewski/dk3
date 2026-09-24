/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "g_local.h"
#include "dk_save_schema.h"

#define DK_PROGRAMS 1024
#define DK_INSTRUCTIONS 16384
#define DK_SCRIPT_JOBS 128
#define DK_SCRIPT_STACK 16
#define DK_SCRIPT_ARGUMENTS 12
#define DK_SCRIPT_FRAME_BUDGET 1024

typedef struct { char *name, *owner; int first, count, repeats, used; } program_t;
typedef struct { char *operation; int argc; char *args[DK_SCRIPT_ARGUMENTS]; } instruction_t;
typedef struct { int program, position, repeats; } frame_t;
typedef struct {
    unsigned int serial, owner, activator;
    int due, depth;
    frame_t frames[DK_SCRIPT_STACK];
} job_t;
static program_t programs[DK_PROGRAMS];
static instruction_t instructions[DK_INSTRUCTIONS];
static job_t jobs[DK_SCRIPT_JOBS];
static char input[1024 * 1024 + 1], scriptMap[MAX_QPATH];
static int programCount, instructionCount, started;
static unsigned int nextSerial;

typedef struct { char name[256]; int count; } validationProgram_t;
static validationProgram_t validationPrograms[DK_PROGRAMS];
static int validationProgramCount;

qboolean DK_PrepareScriptValidation(const char *map) {
    char path[MAX_QPATH], *cursor, *token;
    fileHandle_t file;
    int length, j;
    validationProgramCount = 0;
    Com_sprintf(path, sizeof(path), "dk3/actions/%s.cfg", map);
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length < 0) return qtrue;
    if (length < 1 || length >= sizeof(input)) { if (file) trap_FS_FCloseFile(file); return qfalse; }
    trap_FS_Read(input, length, file); trap_FS_FCloseFile(file); input[length] = 0;
    cursor = input;
    if (strcmp(COM_Parse(&cursor), "dk3_actions") || strcmp(COM_Parse(&cursor), "1")) return qfalse;
    while (*(token = COM_Parse(&cursor))) {
        int used = !strcmp(token, "used"), count;
        char name[256];
        if ((!used && strcmp(token, "script")) || validationProgramCount >= DK_PROGRAMS) return qfalse;
        token = COM_Parse(&cursor);
        if (strlen(token) >= sizeof(name)) return qfalse;
        Q_strncpyz(name, token, sizeof(name));
        COM_Parse(&cursor); COM_Parse(&cursor);
        count = atoi(COM_Parse(&cursor));
        if (count < 0 || count > DK_INSTRUCTIONS) return qfalse;
        if (!used) {
            Q_strncpyz(validationPrograms[validationProgramCount].name, name, sizeof(name));
            validationPrograms[validationProgramCount++].count = count;
        }
        for (j = 0; j < count; ++j) {
            int k, argc;
            COM_Parse(&cursor); argc = atoi(COM_Parse(&cursor));
            if (argc < 0 || argc > DK_SCRIPT_ARGUMENTS) return qfalse;
            for (k = 0; k < argc; ++k) COM_Parse(&cursor);
            if (!cursor) return qfalse;
        }
    }
    return qtrue;
}

static void Diagnostic(job_t *job, const char *operation, const char *message) {
    const char *program = job && job->depth ? programs[job->frames[job->depth - 1].program].name : "load";
    G_Printf("dk3: map %s script %s actor %u operation %s: %s\n", scriptMap, program,
             job ? job->owner : 0, operation, message);
}

gentity_t *DK_FindNamed(const char *name) {
    int i;
    if (!name || !*name) return NULL;
    for (i = 0; i < level.num_entities; ++i) {
        gentity_t *ent = &g_entities[i];
        if (ent->inuse && ((ent->dk.uniqueid && !Q_stricmp(ent->dk.uniqueid, name)) ||
                          (ent->targetname && !Q_stricmp(ent->targetname, name)))) return ent;
    }
    return NULL;
}

void DK_FireNamed(const char *name, gentity_t *source, gentity_t *activator) {
    int i, matched = 0;
    unsigned int sourceId = source ? source->dk.id : 0;
    if (!name || !*name) return;
    for (i = 0; i < level.num_entities; ++i) {
        gentity_t *ent = &g_entities[i];
        if (!ent->inuse || !ent->use || !ent->targetname || Q_stricmp(ent->targetname, name)) continue;
        ++matched;
        if (trap_Cvar_VariableIntegerValue("developer"))
            G_Printf("dk3 target %s: %u (%s) -> %u (%s) name %s activator %u time %d\n", scriptMap,
                sourceId, source && source->inuse ? source->classname : "none", ent->dk.id, ent->classname,
                name, activator ? activator->dk.id : 0, level.time);
        ent->use(ent, DK_FindEntity(sourceId), activator);
    }
    if (!matched && trap_Cvar_VariableIntegerValue("developer"))
        G_Printf("dk3 target %s: source %u name %s has no active recipient\n", scriptMap, sourceId, name);
}

static int Program(const char *name, qboolean used) {
    int i;
    for (i = 0; i < programCount; ++i)
        if (programs[i].used == used && !Q_stricmp(programs[i].name, name)) return i;
    return -1;
}

static char *Token(char **cursor) {
    char *value = COM_Parse(cursor);
    if (!*cursor) G_Error("dk3: map %s: incomplete action program", scriptMap);
    return G_NewString(value);
}

static int Integer(char **cursor, int minimum, int maximum) {
    char *text = Token(cursor), *p = text;
    int value;
    if (*p == '-') ++p;
    if (!*p) G_Error("dk3: map %s: missing script integer", scriptMap);
    while (*p >= '0' && *p <= '9') ++p;
    value = atoi(text);
    if (*p || strlen(text) > 9 || value < minimum || value > maximum)
        G_Error("dk3: map %s: invalid script integer %s", scriptMap, text);
    return value;
}

void DK_LoadScripts(const char *map) {
    char path[MAX_QPATH], *cursor, *kind;
    fileHandle_t file;
    int length, i, j;
    Q_strncpyz(scriptMap, map, sizeof(scriptMap));
    memset(jobs, 0, sizeof(jobs));
    programCount = instructionCount = started = 0;
    nextSerial = 1;
    Com_sprintf(path, sizeof(path), "dk3/actions/%s.cfg", map);
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length < 0) return; /* Most maps do not contain action programs. */
    if (length == 0 || length >= sizeof(input)) G_Error("dk3: %s: invalid program size", path);
    trap_FS_Read(input, length, file); trap_FS_FCloseFile(file);
    input[length] = 0; cursor = input;
    if (strcmp(COM_Parse(&cursor), "dk3_actions") || strcmp(COM_Parse(&cursor), "1"))
        G_Error("dk3: %s: unsupported action format", path);
    while (*(kind = COM_Parse(&cursor))) {
        program_t *program;
        int used = !strcmp(kind, "used");
        if ((!used && strcmp(kind, "script")) || programCount == DK_PROGRAMS)
            G_Error("dk3: %s: invalid declaration or program limit", path);
        program = &programs[programCount++];
        program->used = used;
        program->name = Token(&cursor);
        program->owner = Token(&cursor);
        program->repeats = Integer(&cursor, used ? 0 : -1, used ? 3600000 : 100000);
        program->first = instructionCount;
        program->count = Integer(&cursor, 0, DK_INSTRUCTIONS - instructionCount);
        for (i = 0; i < program->count; ++i) {
            instruction_t *instruction = &instructions[instructionCount++];
            instruction->operation = Token(&cursor);
            instruction->argc = Integer(&cursor, 0, DK_SCRIPT_ARGUMENTS);
            for (j = 0; j < instruction->argc; ++j) instruction->args[j] = Token(&cursor);
        }
    }
    G_Printf("dk3: %s: %d programs, %d instructions\n", path, programCount, instructionCount);
}

qboolean DK_StartScript(const char *name, gentity_t *owner, gentity_t *activator, qboolean urgent) {
    int index = Program(name, qfalse), i;
    job_t *job;
    if (index < 0) { Diagnostic(NULL, "start", va("unknown script %s", name)); return qfalse; }
    if (*programs[index].owner) {
        gentity_t *declared = DK_FindNamed(programs[index].owner);
        if (declared) owner = declared;
        else Diagnostic(NULL, "start", va("declared owner %s missing", programs[index].owner));
    }
    if (urgent && owner) for (i = 0; i < DK_SCRIPT_JOBS; ++i)
        if (jobs[i].owner == owner->dk.id) jobs[i].serial = 0;
    for (i = 0; i < DK_SCRIPT_JOBS && jobs[i].serial; ++i) {}
    if (i == DK_SCRIPT_JOBS) { Diagnostic(NULL, "start", "script job limit reached"); return qfalse; }
    job = &jobs[i];
    memset(job, 0, sizeof(*job));
    job->serial = nextSerial++;
    job->owner = owner ? owner->dk.id : 0;
    job->activator = activator ? activator->dk.id : 0;
    job->depth = 1;
    job->due = level.time;
    job->frames[0].program = index;
    job->frames[0].repeats = programs[index].repeats;
    return qtrue;
}

qboolean DK_UseActorScript(gentity_t *actor, gentity_t *activator) {
    int index, i, count;
    program_t *program;
    instruction_t *selected = NULL;
    if (!actor->dk.uniqueid || level.time < actor->dk.nextUse) return qfalse;
    index = Program(actor->dk.uniqueid, qtrue);
    if (index < 0) return qfalse;
    program = &programs[index];
    count = ++actor->dk.uses;
    for (i = 0; i < program->count; ++i) {
        instruction_t *instruction = &instructions[program->first + i];
        if (!strcmp(instruction->operation, "idle") && !selected) selected = instruction;
        if (atoi(instruction->operation) == count) { selected = instruction; break; }
    }
    actor->dk.nextUse = level.time + program->repeats;
    if (!selected) return qfalse;
    index = (actor->dk.uses - 1) % selected->argc;
    return DK_StartScript(selected->args[index], actor, activator, qtrue);
}

static float Number(job_t *job, const instruction_t *instruction, int index) {
    const char *text = instruction->args[index], *p = text;
    qboolean digit = qfalse;
    float value;
    if (*p == '-' || *p == '+') ++p;
    while (*p >= '0' && *p <= '9') { digit = qtrue; ++p; }
    if (*p == '.') { ++p; while (*p >= '0' && *p <= '9') { digit = qtrue; ++p; } }
    value = atof(text);
    if (!digit || *p || Q_isnan(value) || fabs(value) > 1000000) {
        Diagnostic(job, instruction->operation, va("invalid number %s", text));
        job->serial = 0;
        return 0;
    }
    return value;
}

static qboolean Execute(job_t *job, instruction_t *instruction) {
    const char *op = instruction->operation;
    char **args = instruction->args;
    gentity_t *owner = DK_FindEntity(job->owner), *activator = DK_FindEntity(job->activator), *target;
    int i;
    if (!Q_stricmp(op, "spawn")) {
        vec3_t origin;
        if (DK_FindNamed(args[1])) { Diagnostic(job, op, "unique identifier already exists"); return qfalse; }
        for (i = 0; i < 3; ++i) origin[i] = Number(job, instruction, i + 2);
        if (!job->serial) return qfalse;
        target = G_Spawn();
        target->classname = G_NewString(args[0]);
        target->dk.uniqueid = G_NewString(args[1]);
        VectorCopy(origin, target->s.origin);
        target->s.angles[YAW] = Number(job, instruction, 5);
        if (!DK_SpawnActor(target)) { G_FreeEntity(target); Diagnostic(job, op, va("unknown actor %s", args[0])); return qfalse; }
        target->dk.ignorePlayer = !Q_stricmp(args[6], "false");
        if (instruction->argc > 7) target->targetname = G_NewString(args[7]);
        if (instruction->argc > 8) target->dk.deathTarget = G_NewString(args[8]);
    } else if (!Q_stricmp(op, "set_state")) {
        target = DK_FindNamed(args[0]);
        if (!DK_ActorState(target, args[1], instruction->argc > 2 ? args[2] : "")) {
            Diagnostic(job, op, va("actor %s or state %s unavailable", args[0], args[1])); return qfalse;
        }
    } else if (!Q_stricmp(op, "send_message") || !Q_stricmp(op, "send_urgent_message")) {
        target = DK_FindNamed(args[0]);
        if (!target) { Diagnostic(job, op, va("recipient %s missing", args[0])); return qfalse; }
        return DK_StartScript(args[1], target, activator, !Q_stricmp(op, "send_urgent_message"));
    } else if (!Q_stricmp(op, "call") || !Q_stricmp(op, "random_script")) {
        int index = Program(args[!Q_stricmp(op, "call") ? 0 : (job->serial + level.framenum) % instruction->argc], qfalse);
        frame_t *frame;
        if (index < 0 || job->depth == DK_SCRIPT_STACK) { Diagnostic(job, op, "unknown script or call stack exhausted"); return qfalse; }
        frame = &job->frames[job->depth++];
        frame->program = index; frame->position = 0; frame->repeats = programs[index].repeats;
    } else if (!Q_stricmp(op, "use")) {
        target = DK_FindNamed(args[0]);
        if (!target || !target->use) { Diagnostic(job, op, va("recipient %s unavailable", args[0])); return qfalse; }
        target->use(target, owner, activator);
    }
    else if (!Q_stricmp(op, "remove")) {
        target = DK_FindNamed(args[0]);
        if (target) G_FreeEntity(target);
    } else if (!Q_stricmp(op, "animate")) {
        int duration;
        if (!owner || !owner->dk.actorKind) { Diagnostic(job, op, "actor missing"); return qfalse; }
        duration = DK_ActorAnimate(owner, args[0], instruction->argc > 1 ? Number(job, instruction, 1) : 1);
        if (duration < 0) {
            /* Supplied scripts sometimes reference a sequence absent from the
               supplied model (e1m1c's skinny worker requests aaeaa). Preserve
               its pose and continue the remaining animation/path commands;
               a missing visual clip must not discard the actor's whole job. */
            Diagnostic(job, op, va("model %s has no animation %s; retaining pose and continuing",
                owner->model ? owner->model : "<unnamed>", args[0]));
            return qtrue;
        }
        job->due = level.time + duration;
    } else if (!Q_stricmp(op, "set_moving_animation")) {
        if (!owner) { Diagnostic(job, op, "actor missing"); return qfalse; }
        owner->dk.movingAnimation = args[0];
    } else if (!Q_stricmp(op, "face_angle")) {
        if (!owner) { Diagnostic(job, op, "actor missing"); return qfalse; }
        for (i = 0; i < 3; ++i) owner->dk.turnGoal[i] = Number(job, instruction, i);
        owner->dk.turnActive = 1;
        if (owner->dk.yawSpeed <= 0) owner->dk.yawSpeed = 90;
    } else if (!Q_stricmp(op, "wait")) job->due = level.time + (int)(Number(job, instruction, 0) * 1000);
    else if (!Q_stricmp(op, "sound") || !Q_stricmp(op, "stream_sound")) {
        int sound = DK_SoundIndex(args[0]);
        target = instruction->argc > 1 ? DK_FindNamed(args[1]) : owner;
        if (instruction->argc > 1 && !target) { Diagnostic(job, op, va("sound actor %s missing", args[1])); return qfalse; }
        if (!Q_stricmp(op, "stream_sound") || !target) {
            gentity_t *event = G_TempEntity(target ? target->r.currentOrigin : vec3_origin, EV_GLOBAL_SOUND);
            event->s.eventParm = sound;
            event->r.svFlags |= SVF_BROADCAST;
        } else G_Sound(target, CHAN_VOICE, sound);
    } else if (!Q_stricmp(op, "move_to")) {
        vec3_t goal;
        if (!owner || !owner->dk.actorKind) { Diagnostic(job, op, "actor missing"); return qfalse; }
        for (i = 0; i < 3; ++i) goal[i] = Number(job, instruction, i);
        DK_ActorMoveTo(owner, goal);
    } else if (!Q_stricmp(op, "attack")) {
        target = DK_FindNamed(args[0]);
        if (!owner || !target || !owner->dk.actorKind) { Diagnostic(job, op, "attacker or victim missing"); return qfalse; }
        owner->enemy = target; owner->dk.ignorePlayer = 0;
    } else if (!Q_stricmp(op, "print")) {
        G_Printf("dk3: script %s: %s\n", scriptMap, args[0]);
    } else {
        Diagnostic(job, op, "unsupported operation");
        return qfalse;
    }
    return qtrue;
}

void DK_RunScripts(void) {
    int i, j, budget = DK_SCRIPT_FRAME_BUDGET;
    if (!started) {
        if (!g_entities[0].client || g_entities[0].client->pers.connected != CON_CONNECTED) return;
        started = 1;
        if (Program("$level_start", qfalse) >= 0) DK_StartScript("$level_start", NULL, &g_entities[0], qfalse);
    }
    for (i = 0; i < DK_SCRIPT_JOBS && budget > 0; ++i) {
        job_t *job = &jobs[i];
        if (!job->serial || job->due > level.time) continue;
        if (job->owner) {
            for (j = 0; j < DK_SCRIPT_JOBS; ++j)
                if (jobs[j].serial && jobs[j].serial < job->serial && jobs[j].owner == job->owner) break;
            if (j < DK_SCRIPT_JOBS) continue;
            if (DK_FindEntity(job->owner) && (DK_FindEntity(job->owner)->dk.moveActive || DK_FindEntity(job->owner)->dk.turnActive)) continue;
            if (!DK_FindEntity(job->owner)) { Diagnostic(job, "resume", "owner removed"); job->serial = 0; continue; }
        }
        while (job->serial && job->depth && job->due <= level.time && budget-- > 0) {
            frame_t *frame = &job->frames[job->depth - 1];
            program_t *program = &programs[frame->program];
            if (frame->position == program->count) {
                if (frame->repeats == -1 || --frame->repeats > 0) { frame->position = 0; job->due = level.time + 1; }
                else if (--job->depth == 0) job->serial = 0;
                continue;
            }
            if (!Execute(job, &instructions[program->first + frame->position++])) job->serial = 0;
            if (job->owner) {
                gentity_t *actor = DK_FindEntity(job->owner);
                if (actor && (actor->dk.moveActive || actor->dk.turnActive)) break;
            }
        }
    }
}

/* Program names and instruction positions are stable data; a save contains neither
   callback addresses nor executable instructions. Asset identity is checked by the loader. */
typedef struct {
    unsigned int owner, activator;
    int due, depth;
    int position[DK_SCRIPT_STACK], repeats[DK_SCRIPT_STACK];
    char *program[DK_SCRIPT_STACK];
} savedJob_t;
static const dkSaveMember_t jobMembers[] = {
    {"owner", DK_SAVE_INT, offsetof(savedJob_t, owner), 1, qfalse},
    {"activator", DK_SAVE_INT, offsetof(savedJob_t, activator), 1, qfalse},
    {"due", DK_SAVE_INT, offsetof(savedJob_t, due), 1, qtrue},
    {"depth", DK_SAVE_INT, offsetof(savedJob_t, depth), 1, qfalse},
    {"position", DK_SAVE_INT, offsetof(savedJob_t, position), DK_SCRIPT_STACK, qfalse},
    {"repeats", DK_SAVE_INT, offsetof(savedJob_t, repeats), DK_SCRIPT_STACK, qfalse},
#define PROGRAM_FIELD(n) {"program_" #n, DK_SAVE_TEXT, offsetof(savedJob_t, program[n]), 1, qfalse}
    PROGRAM_FIELD(0), PROGRAM_FIELD(1), PROGRAM_FIELD(2), PROGRAM_FIELD(3),
    PROGRAM_FIELD(4), PROGRAM_FIELD(5), PROGRAM_FIELD(6), PROGRAM_FIELD(7),
    PROGRAM_FIELD(8), PROGRAM_FIELD(9), PROGRAM_FIELD(10), PROGRAM_FIELD(11),
    PROGRAM_FIELD(12), PROGRAM_FIELD(13), PROGRAM_FIELD(14), PROGRAM_FIELD(15)
#undef PROGRAM_FIELD
};

qboolean DK_WriteScriptState(dkSaveWriter_t *writer) {
    int state[2], i, j;
    state[0] = started; state[1] = nextSerial;
    if (!DK_SaveRecord(writer, "script_state", 0) || !DK_SaveInts(writer, "state", state, 2)) return qfalse;
    for (i = 0; i < DK_SCRIPT_JOBS; ++i) if (jobs[i].serial) {
        savedJob_t saved;
        memset(&saved, 0, sizeof(saved));
        saved.owner = DK_FindEntity(jobs[i].owner) ? jobs[i].owner : 0;
        saved.activator = DK_FindEntity(jobs[i].activator) ? jobs[i].activator : 0;
        saved.due = jobs[i].due; saved.depth = jobs[i].depth;
        for (j = 0; j < saved.depth; ++j) {
            saved.program[j] = programs[jobs[i].frames[j].program].name;
            saved.position[j] = jobs[i].frames[j].position;
            saved.repeats[j] = jobs[i].frames[j].repeats;
        }
        if (!DK_SaveRecord(writer, "script_job", jobs[i].serial) ||
            !DK_SaveObject(writer, &saved, jobMembers, ARRAY_LEN(jobMembers))) return qfalse;
    }
    return qtrue;
}

qboolean DK_ReadScriptState(dkSaveReader_t *reader, const char *kind, unsigned int id, qboolean apply) {
    if (!strcmp(kind, "script_state")) {
        dkSaveField_t field;
        if (id || !DK_SaveNextField(reader, &field) || strcmp(field.name, "state") || field.type != DK_SAVE_INT ||
            field.count != 2 || reader->fieldsLeft || DK_SaveInt(&field, 0) < 0 || DK_SaveInt(&field, 0) > 1 ||
            DK_SaveInt(&field, 1) < 1) return qfalse;
        if (apply) { memset(jobs, 0, sizeof(jobs)); started = DK_SaveInt(&field, 0); nextSerial = DK_SaveInt(&field, 1); }
        return qtrue;
    }
    if (!strcmp(kind, "script_job")) {
        savedJob_t saved;
        job_t job;
        char storage[4096];
        dkSaveStrings_t strings = {storage, sizeof(storage), 0};
        int i, j;
        memset(&saved, 0, sizeof(saved)); memset(&job, 0, sizeof(job));
        if (!id || !DK_ReadObject(reader, &saved, jobMembers, ARRAY_LEN(jobMembers), &strings) ||
            saved.depth < 1 || saved.depth > DK_SCRIPT_STACK) return qfalse;
        job.serial = id; job.owner = saved.owner; job.activator = saved.activator;
        job.depth = saved.depth; job.due = saved.due;
        if (!DK_SaveReferenceExists(saved.owner) || !DK_SaveReferenceExists(saved.activator)) return qfalse;
        for (i = 0; i < saved.depth; ++i) {
            int program = -1, length = 0;
            if (saved.program[i]) {
                if (apply) {
                    program = Program(saved.program[i], qfalse);
                    if (program >= 0) length = programs[program].count;
                } else for (j = 0; j < validationProgramCount; ++j)
                    if (!Q_stricmp(validationPrograms[j].name, saved.program[i])) {
                        program = j; length = validationPrograms[j].count; break;
                    }
            }
            if (program < 0 || saved.position[i] < 0 || saved.position[i] > length ||
                saved.repeats[i] < -1 || saved.repeats[i] > 100000 || saved.repeats[i] == 0) return qfalse;
            job.frames[i].program = program; job.frames[i].position = saved.position[i]; job.frames[i].repeats = saved.repeats[i];
        }
        if (apply) {
            for (j = 0; j < DK_SCRIPT_JOBS && jobs[j].serial; ++j) {}
            if (j == DK_SCRIPT_JOBS) return qfalse;
            jobs[j] = job;
        }
        return qtrue;
    }
    return qfalse;
}
