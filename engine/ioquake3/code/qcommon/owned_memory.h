/* SPDX-License-Identifier: GPL-2.0-or-later
 * Releasable renderer/navigation storage for resident regions. These imports
 * have explicit lifetimes, independent of the original single-map zone. */
#ifndef DK3_OWNED_MEMORY_H
#define DK3_OWNED_MEMORY_H
#include <stdlib.h>
#include <stddef.h>
typedef union ownedBlock_u ownedBlock_t;
typedef struct { ownedBlock_t *first; size_t bytes; } ownedHeap_t;
union ownedBlock_u {
    struct { ownedBlock_t *next, *previous; ownedHeap_t *owner; size_t size; } block;
    long double alignment;
};
static inline void *Owned_Alloc(ownedHeap_t *heap, int size) {
    ownedBlock_t *block;
    if (size < 0 || heap->bytes > (size_t)-1 - (size_t)size) return NULL;
    block = malloc(sizeof(*block) + (size_t)size);
    if (!block) return NULL;
    block->block.previous = NULL;
    block->block.next = heap->first;
    block->block.owner = heap;
    block->block.size = (size_t)size;
    if (heap->first) heap->first->block.previous = block;
    heap->first = block;
    heap->bytes += (size_t)size;
    return block + 1;
}
static inline void Owned_Free(void *pointer) {
    ownedBlock_t *block;
    ownedHeap_t *heap;
    if (!pointer) return;
    block = (ownedBlock_t *)pointer - 1;
    heap = block->block.owner;
    if (block->block.previous) block->block.previous->block.next = block->block.next;
    else heap->first = block->block.next;
    if (block->block.next) block->block.next->block.previous = block->block.previous;
    heap->bytes -= block->block.size;
    free(block);
}
static inline void Owned_Clear(ownedHeap_t *heap) {
    while (heap->first) Owned_Free(heap->first + 1);
}
#endif
