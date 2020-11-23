#ifndef GLIRC_MARSHAL
#define GLIRC_MARSHAL

#include <string.h>
#include <lua.h>

#include "glirc-api.h"

static inline struct glirc *get_glirc(lua_State *L)
{
        return *(struct glirc **)lua_getextraspace(L);
}

static inline void set_glirc(lua_State *L, struct glirc *G)
{
        *(struct glirc **)lua_getextraspace(L) = G;
}

void push_glirc_chat(lua_State *L, const struct glirc_chat *chat);
void push_glirc_message(lua_State *L, const struct glirc_message *msg);
void push_glirc_command(lua_State *L, const struct glirc_command *cmd);
void push_glirc_string(lua_State *L, const struct glirc_string *s);
void import_string_array(lua_State *L, char **list);
int get_glirc_string(lua_State *L, int i, struct glirc_string *s);

#endif
