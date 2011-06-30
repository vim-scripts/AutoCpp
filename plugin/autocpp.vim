" ========================================
" GENERATED FILE. DO NOT EDIT!!!
" ========================================

" ========================================================================
" Author:  Dmitry Ermolov <epdmitry@yandex.ru>
" License: This program is free software. It comes without any warranty,
"          to the extent permitted by applicable law. You can redistribute
"          it and/or modify it under the terms of the Do What The Fuck You 
"          Want To Public License, Version 2, as published by Sam Hocevar.
"          See http://sam.zoy.org/wtfpl/COPYING for more details.
" 
" https://github.com/9uMaH/autocpp
" ========================================================================

if exists('s:plugin_loaded') || version < 700
    finish
endif
let s:plugin_loaded = 1

"""""""""""""
" Keybindings
"""""""""""""

" Typify
map <silent> <C-j> :AutoCppTypify<CR>
imap <silent> <C-j> <C-O>:AutoCppTypify<CR>

" Print variable type
map <silent> <C-n> :AutoCppPrintVariableType<CR>

"""""""""""""
" Commands
"""""""""""""

command -nargs=0 AutoCppGotoFunctionBegin call s:GotoFunctionBegin()
command -nargs=0 AutoCppPrintFunctionName call s:PrintFunctionName()
command -nargs=0 AutoCppPrintFullFunctionName call s:PrintFullFunctionName()
command -nargs=0 AutoCppGotoVariableDeclaration call s:GotoVariableDeclaration()
command -nargs=0 AutoCppPrintVariableType call s:PrintVariableType()
command -nargs=0 AutoCppTypify call s:Typify()

"""""""""""""
" Constants
"""""""""""""

let s:KEYWORDS = {'const' : 1, 'do' : 1, 'except' : 1, 'for' : 1, 'if' : 1, 'struct' : 1, 'switch' : 1, 'try' : 1, 'union' : 1, 'while' : 1, 'return' : 1}

" Exceptions, that are used in this module
"   'parse error' -- cannot parse code
"   'not inside function' -- cursor is not positioned inside function
"   'not found' -- can't find something
"   'value error' -- function can't process given arguments

let s:ERRORS = {}
let s:ERRORS['not inside function'] = 'Error: cursor is not inside function'

let s:NAME_RE = '[A-Za-z_]\w*'
let s:TYPENAME_SUFFIX_LIST = ['::const_iterator', '::iterator']

let s:type_suggest = [] " list of dicts {line, pos}
let s:type_suggest_index = 0


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Interface functions.
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Moves cursor to the beginning of the function, which cursor is currently in
function s:GotoFunctionBegin()
    try
        let l:funcinfo = s:get_current_function_info()
        normal m'
        call cursor(l:funcinfo.declpos[1:2])
    catch /^not inside function$/
        echom s:ERRORS['not inside function']
    endtry
endfunction

" Print the name of the function, which cursor is currently in
function s:PrintFunctionName()
    try
        let l:funcinfo = s:get_current_function_info()
        echom l:funcinfo.name
    catch /^not inside function$/
        echom s:ERRORS['not inside function']
    endtry
endfunction

" Print full name of the function, which cursor is currently in.
" Name contains class name, namespace name.
function s:PrintFullFunctionName()
    try
        let l:funcinfo = s:get_current_function_info()
        echom l:funcinfo.namespace . l:funcinfo.name
    catch /^not inside function$/
        echom s:ERRORS['not inside function']
    endtry
endfunction

" Moves cursor to declaration of variable, that is under cursor.
function s:GotoVariableDeclaration()
    try
        let varname = expand('<cword>')
        let varinfo = s:find_declaration(varname)
        normal m'
        call cursor(varinfo.pos[1:2])
    catch /^not inside function$/
        echom "Error: cursor is not inside function"
    catch /^not found$/
        echom "Error: declaration of variable '" . varname . "' is not found"
    catch /^value error$/
        echom "Error: '" . varname . "' is not a variable name"
    endtry
endfunction

" Prints the type of the variable under cursor
function s:PrintVariableType()
    try
        let varname = expand('<cword>')
        let varinfo = s:find_declaration(varname)
        echom varinfo.type
    catch /^not inside function$/
        echom "Error: cursor is not inside function"
    catch /^not found$/
        echom "Error: declaration of variable '" . varname . "' is not found"
    catch /^value error$/
        echom "Error: '" . varname . "' is not a variable name"
    endtry
endfunction

" inserts type of left part in first assignment in the string
function s:Typify()
    if s:nothing_changed_since_last_typifization()
        let suggest_len = len(s:type_suggest)
        let s:type_suggest_index = (s:type_suggest_index + 1) % suggest_len

        let newline = s:type_suggest[s:type_suggest_index].line
        let newpos = s:type_suggest[s:type_suggest_index].pos

        call setline(newpos[1], newline)
        call setpos('.', newpos)
        return
    endif

    try
        let typifizationinfo = s:typify_current_assignment()
        let typepos = typifizationinfo.typepos
        let curline = getline(typepos[1])
        let linebeg = strpart(curline, 0, typepos[2]-1)
        let lineend = strpart(curline, typepos[2]-1)
        let typename_list = typifizationinfo.typename_list
        let curpos = getpos('.')

        let s:type_suggest = [s:newsuggest(getline('.'), getpos('.'))]
        let s:type_suggest_index = 0

        for typename in typename_list
            let typename = typename . ' '
            let suggestline = linebeg . typename . lineend
            let suggestpos = curpos[:]
            if s:cmppos(curpos, typepos) > 0
                let suggestpos[2] += strlen(typename)
            endif
            call add(s:type_suggest, s:newsuggest(suggestline, suggestpos))
        endfor
        call s:Typify()
    catch /^parse error$/
        echom "Error: can't find untypified assignment on current line"
    catch /^not found$/
        echom "Error: can't find declaration"
    endtry
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" High level functions.
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Returns a dictionary
"   name -- name of a function
"   namespace -- namespace of a function
"   returntype -- type of return value
"   declpos -- position (in cursor format) where function name begins
"   arguments -- string representing a variables of the function
"   argumentposs -- pair: pos of left brace, pos of right brace
"   bodypos -- position of first curly brace of
function s:get_current_function_info()
    let original_pos = getpos('.')
    try
        while 1
            let l:found = searchpair('{', '', '}', 'bW')
            if !l:found
                throw 'not inside function'
            endif
            let bodypos = getpos('.')
            try
                call s:token_backward()
                let l:function_info = s:parse_function_declaration()
                let l:function_info.declpos = getpos('.')
                let function_info.bodypos = bodypos
                return l:function_info
            catch /^parse error$/
            endtry
        endwhile
    finally
        call setpos('.', original_pos)
    endtry
endfunction

" Finds declaration of the given variable.
" Searches backwards.
" Trys following locations:
" current function/method body, argument list.
"
" return dictionary
"   type
"   pos
"
" TODO: search in the class
"
" throws 
"   'value error' -- if argument seems to be not a variable name
"   'not found' -- if function can't find declaration
function s:find_declaration(varname)
    let original_pos = getpos('.')
    let function_info = s:get_current_function_info()
    try
        " check variable name
        if a:varname !~ '[A-Za-z_]\w*' || has_key(s:KEYWORDS, a:varname)
            throw 'value error'
        endif

        " search in the body
        try
            let funbegin = function_info.bodypos
            let funend = getpos('.')
            return s:search_declaration_in_range(a:varname, funbegin, funend)
        catch /^not found$/
        endtry

        " search in the arguments
        try
            let [argbegin, argend] = function_info.argumentposs
            return s:search_declaration_in_range(a:varname, argbegin, argend)
        catch /^not found$/
        endtry
        throw 'not found'
    finally
        call setpos('.', original_pos)
    endtry
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" - Finds first assignment in current string.
" - Finds out what is the expected type of left part of assignment.
"
" Return dictionary
"   typepos -- position where typename should be inserted
"   typename_list -- list of possible types of the left part of assignment
function s:typify_current_assignment()
    let original_pos = getpos('.')
    try
        " go to string beginning
        call cursor(original_pos[1], 1)
        " go to first '=' symbol
        let found = search('=', 'Wc', original_pos[1])
        if found <= 0
            throw 'parse error'
        endif

        " parse assignment from inside
        let assignmentinfo = s:parse_assignment_from_inside()
        let pos = getpos('.')

        " get object name
        let rightpart = assignmentinfo.rightpart
        let brace_pos = match(rightpart, '(')
        if brace_pos >= 0
            let rightpart = rightpart[: brace_pos-1]
        endif

        let function_name = matchstr(rightpart, s:NAME_RE . '$')
        if len(function_name) == 0
            throw 'parse error'
        endif

        let object_name = matchstr(rightpart, '^' . s:NAME_RE)
        if len(object_name) == 0
            throw 'parse error'
        endif

        let varinfo = s:find_declaration(object_name)
        let typename_list = []
        for typename in s:TYPENAME_SUFFIX_LIST
            let tmp = varinfo.basetype . typename
            call add(typename_list, tmp)
        endfor
        " understand type
        return {'typepos': pos, 'typename_list':typename_list}
    finally
        call setpos('.', original_pos)
    endtry
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Searching
"

" Searches declaration of variable inside given range
" returns dictionary
"   type
"   pos
function s:search_declaration_in_range(varname, beginpos, endpos)
    let original_pos = getpos('.')
    call setpos('.', a:endpos)
    let varnameregexp = '\<' . a:varname . '\>'
    let searchflags = 'bcW' " first time we allow match in the current position
    while 1
        let found = searchpair('{', varnameregexp, '}', searchflags)
        let searchflags = 'bW'
        let curpos = getpos('.')

        if found <= 0 || s:cmppos(a:beginpos, curpos) != -1
            call setpos('.', original_pos)
            throw 'not found'
        elseif s:current_char() == '{'
            continue
        endif

        try
            let result = s:parse_declaration_from_inside()
            if result.name == a:varname
                let result.pos = getpos('.')
                return result
            else
                call setpos('.', curpos)
            endif
        catch /^parse error$/
            call setpos('.', curpos)
        endtry
    endwhile
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Parsing
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Moves cursor to variable declaration beginnig and returns dictionary
"   name
"   pos
"   type
function s:parse_declaration_from_inside()
    " STBEG TYPE NAME [ ARGS ] STEND
    let original_pos = getpos('.')
    let stbeg_regexp = '[{},;(]'
    let stend_regexp = '[),;=(]'

    " search statement begin backward
    let found = search(stbeg_regexp, 'bW')
    if found <= 0
        call setopos('.', original_pos)
        throw 'not found'
    endif
    let stbeg_pos = getpos('.')

    " search statement end or '=' forward
    let found = search(stend_regexp, 'W')
    if found <= 0
        call setopos('.', original_pos)
        throw 'parse error'
    endif
    let stend_pos = getpos('.')

    call s:token_backward()

    " (MAYBE
    "   (ANY
    "       arguments
    "       (REPLACEVAR 'l:arrayness arrayidx)))
    let arrayness = ''
    try
        call s:parse_arguments()
        call s:token_backward()
    catch /^parse error$/
        try
            let arrayness = s:parse_token('\[\d*\]').token
            call s:token_backward()
        catch /^parse error$/
        endtry
    endtry

    try
        let name = s:parse_name()['name']
        call s:token_backward()
        let result = s:parse_type()
        let result.type .= arrayness
        let declpos = getpos('.')
    finally
        call setpos('.', original_pos)
    endtry
    call setpos('.', declpos)
    let result.pos = declpos
    let result.name = name
    return result
endfunction

"   In case of success moves cursor to declaration begin and returns
"   a dictionary:
"       name
"       namespace
"       returntype
"       arguments
"       argumentsposs
"   throw exception 'parse error' otherwise
function s:parse_function_declaration()
    "     (SEQ
    "       (MAYBE (ANY const mutable))
    "       (SAVEINFO 'argument_info arguments)
    "       (SAVEINFO 'identifier_info identifier)
    "       (SAVEINFO 'type_info type))
    " 
    " generated code {{{
    " (SEQ
    let l:__origpos_1 = getpos('.')
    try
        " (MAYBE
        try
            " (ANY
            try
                call s:parse_const() " const
                call s:token_backward()
            catch /^parse error$/
                call s:parse_mutable() " mutable
                call s:token_backward()
            endtry
            " )
        catch /^parse error$/
        endtry
        " )
        let argument_info = s:parse_arguments() " arguments
        call s:token_backward()
        let identifier_info = s:parse_identifier() " identifier
        call s:token_backward()
        let type_info = s:parse_type() " type
        call s:token_backward()
    let l:__newpos_2 = getpos('.')
    finally
        call setpos('.', l:__origpos_1)
    endtry
    call setpos('.', l:__newpos_2)
    " )
    call s:token_forward()
    " }}} endof generated code

    let res = {} 
    let res.name = l:identifier_info.name
    let res.namespace = l:identifier_info.namespace
    let res.returntype = type_info.type
    let res.arguments = argument_info.arguments
    let res.argumentposs = argument_info.argumentposs
    return l:res
endfunction

" sets cursor to the next token backward
function s:token_backward()
    let found = search('\S\s*', 'bW')
    if found < 0
        throw 'end of file'
    endif
endfunction

" set cursor to the next token forward
function s:token_forward()
    let found = search('\s*\S', 'We')
    if found < 0
        throw 'end of file'
    endif
endfunction


function s:skip_spaces()
    let found = search('\S\s*', 'cbW')
    if found < 0
        throw 'end of file'
    endif
endfunction

" Parse argument list in function declaration, for example:
" (int argc, char** " argv)
" In case of success moves cursor to the left brace and returns dictionary
"   arguments
"   poss
" 
" Throws exception 'parse error' otherwise
function s:parse_arguments()
    let info = s:parse_braces('(', ')')
    return {'arguments': info.text, 'argumentposs': info.poss}
endfunction

" Parse template arguments list
" returns 
"   text
"   poss
function s:parse_templates()
    let original_pos = getpos('.')
    let info = s:parse_braces('<', '>')
    if info.text !~ '[<>, A-Za-z0-9_]*'
        call setpos('.', original_pos)
        throw 'parse error'
    endif
    return info
endfunction

" Parse argument list in function declaration, for example:
" (int argc, char** argv)
" In case of success moves cursor to the left brace and returns dictionary
"   text
"   poss
" 
" Throws exception 'parse error' otherwise
function s:parse_braces(left, right)
    let original_pos = getpos('.')
    let l:right_brace_pos = original_pos
    if s:current_char() != a:right
        call setpos('.', original_pos)
        throw 'parse error'
    endif
    let l:linenum = searchpair(a:left, '', a:right, 'bW')
    if l:linenum == 0
        call setpos('.', original_pos)
        throw 'parse error'
    endif
    let left_brace_pos = getpos('.')
    let res = {}
    let res.text = s:text_between(left_brace_pos, right_brace_pos, ' ')
    let res.poss = [left_brace_pos, right_brace_pos]
    return res
endfunction

" returns a dictionary
"   identifier
"   name
"   namespace
function s:parse_identifier()
    let original_pos = getpos('.')
    let l:regexp = '\(\%(::\)\?\%(\w\+::\)*\)\(\w*\)'
    call search(l:regexp, 'bWc')
    let l:identifier_begin = getpos('.')
    let l:text = s:text_between(l:identifier_begin, original_pos, ' ')
    let l:matchlist = matchlist(l:text, l:regexp)
    let l:identifier = l:matchlist[0]
    let l:namespace = l:matchlist[1]
    let l:name = l:matchlist[2]
    if l:identifier == '' || l:name == ''
        call setpos('.', original_pos)
        throw 'parse error'
    endif
    return {'identifier':l:identifier, 'name':l:name, 'namespace':l:namespace}
endfunction

" returns a dictionary
"   name
"   token
function s:parse_name()
    let result = s:parse_token('\<' . s:NAME_RE . '\>')
    let result.name = result.token
    return result
endfunction

function s:parse_templ()
    return s:parse_templates()
endfunction

function s:parse_amp()
    return s:parse_token('&')
endfunction

function s:parse_const()
    return s:parse_token('\<const\>')
endfunction

function s:parse_mutable()
    return s:parse_token('\<mutable\>')
endfunction

function s:parse_star()
    return s:parse_token('*')
endfunction

function s:parse_ns()
    return s:parse_token('::')
endfunction

function s:parse_dot()
    return s:parse_token('[.]')
endfunction

function s:parse_arrow()
    return s:parse_token('->')
endfunction

function s:parse_eq()
    return s:parse_token('=')
endfunction

" parses token that is defined by regexp
" returns a dictionary
"   token
function s:parse_token(regexp)
    let original_pos = getpos('.')
    call search(a:regexp, 'bWc')
    let text = s:text_between(getpos('.'), original_pos, ' ')
    let match = matchstr(text, '^' . a:regexp . '$')
    if len(match) == 0
        call setpos('.', original_pos)
        throw 'parse error'
    endif
    return {'token': match}
endfunction

" returns dictionary
"   type
"   basetype
function s:parse_type()
    "     (SAVESTR 'typename
    "     (SEQ
    "       (MAYBE amp)
    "       (MANY (ANY const mutable star))
    "       (SAVESTR 'basetypename
    "         (SEQ
    "           (MAYBE templ)
    "           name
    "           (MANY
    "             (SEQ ns (MAYBE templ) name))))
    "       (MAYBE (ANY const mutable))))
    " 
    " generated code {{{
    " (SAVESTR 'typename
    let l:__origpos_12 = getpos('.')
    " (SEQ
    let l:__origpos_10 = getpos('.')
    try
        " (MAYBE
        try
            call s:parse_amp() " amp
            call s:token_backward()
        catch /^parse error$/
        endtry
        " )
        " (MANY
        try
            while 1
                " (ANY
                try
                    call s:parse_const() " const
                    call s:token_backward()
                catch /^parse error$/
                    try
                        call s:parse_mutable() " mutable
                        call s:token_backward()
                    catch /^parse error$/
                        call s:parse_star() " star
                        call s:token_backward()
                    endtry
                endtry
                " )
        endwhile
        catch /^parse error$/
        endtry
        " )
        " (SAVESTR 'basetypename
        let l:__origpos_9 = getpos('.')
        " (SEQ
        let l:__origpos_7 = getpos('.')
        try
            " (MAYBE
            try
                call s:parse_templ() " templ
                call s:token_backward()
            catch /^parse error$/
            endtry
            " )
            call s:parse_name() " name
            call s:token_backward()
            " (MANY
            try
                while 1
                    " (SEQ
                    let l:__origpos_4 = getpos('.')
                    try
                        call s:parse_ns() " ns
                        call s:token_backward()
                        " (MAYBE
                        try
                            call s:parse_templ() " templ
                            call s:token_backward()
                        catch /^parse error$/
                        endtry
                        " )
                        call s:parse_name() " name
                        call s:token_backward()
                    let l:__newpos_5 = getpos('.')
                    finally
                        call setpos('.', l:__origpos_4)
                    endtry
                    call setpos('.', l:__newpos_5)
                    " )
            endwhile
            catch /^parse error$/
            endtry
            " )
        let l:__newpos_8 = getpos('.')
        finally
            call setpos('.', l:__origpos_7)
        endtry
        call setpos('.', l:__newpos_8)
        " )
        call s:token_forward()
        let basetypename = s:text_between(getpos('.'), l:__origpos_9)
        call s:token_backward()
        " (MAYBE
        try
            " (ANY
            try
                call s:parse_const() " const
                call s:token_backward()
            catch /^parse error$/
                call s:parse_mutable() " mutable
                call s:token_backward()
            endtry
            " )
        catch /^parse error$/
        endtry
        " )
    let l:__newpos_11 = getpos('.')
    finally
        call setpos('.', l:__origpos_10)
    endtry
    call setpos('.', l:__newpos_11)
    " )
    call s:token_forward()
    let typename = s:text_between(getpos('.'), l:__origpos_12)
    call s:token_backward()
    call s:token_forward()
    " }}} endof generated code
    return {'type' : s:normalize(typename), 'basetype' : s:normalize(basetypename)}
endfunction

" Returns dictionary
"   rightpart
"   leftpart
function s:parse_assignment_from_inside()
    let original_pos = getpos('.')

    "(SEQ (SAVESTR 'leftpart name) = (SAVESTR 'rightpart call))

    try
        " position to statement beginning
        let found = search('[{;}(]', 'bW')
        if found <= 0
            throw 'parse error'
        endif
        let statement_beginnig = getpos('.')

        " position to statement ending
        call setpos('.', original_pos)
        let found = search(';\|$', 'W')
        if found <= 0
            throw 'parse error'
        elseif s:current_char() == ';'
            call search('.', 'bW')
        endif
        let statement_ending = getpos('.')

        " parse call
        call s:skip_spaces()
        let callinfo = s:parse_function_call()
        let rightpart = callinfo.token

        " parse =
        call s:token_backward()
        call s:parse_token('=')

        " parse name
        call s:token_backward()
        let nameinfo = s:parse_name()
        call s:token_backward()
        let assignment_begin = getpos('.')
        let leftpart = nameinfo.token

        " ensure that we are at statement beginning
        if s:cmppos(assignment_begin, statement_beginnig) != 0
            throw 'parse error'
        endif
    finally
        call setpos('.', original_pos)
    endtry
    call setpos('.', assignment_begin)
    call s:token_forward()
    return {'leftpart': leftpart, 'rightpart': rightpart}
endfunction

" Returns dictionary
"   token
function s:parse_function_call()
    "     (SAVESTR 'token
    "       (SEQ 
    "         (MAYBE arguments) 
    "         name
    "         (MANY (SEQ
    "             (ANY dot arrow)
    "             name))))
    " 
    " generated code {{{
    " (SAVESTR 'token
    let l:__origpos_18 = getpos('.')
    " (SEQ
    let l:__origpos_16 = getpos('.')
    try
        " (MAYBE
        try
            call s:parse_arguments() " arguments
            call s:token_backward()
        catch /^parse error$/
        endtry
        " )
        call s:parse_name() " name
        call s:token_backward()
        " (MANY
        try
            while 1
                " (SEQ
                let l:__origpos_13 = getpos('.')
                try
                    " (ANY
                    try
                        call s:parse_dot() " dot
                        call s:token_backward()
                    catch /^parse error$/
                        call s:parse_arrow() " arrow
                        call s:token_backward()
                    endtry
                    " )
                    call s:parse_name() " name
                    call s:token_backward()
                let l:__newpos_14 = getpos('.')
                finally
                    call setpos('.', l:__origpos_13)
                endtry
                call setpos('.', l:__newpos_14)
                " )
        endwhile
        catch /^parse error$/
        endtry
        " )
    let l:__newpos_17 = getpos('.')
    finally
        call setpos('.', l:__origpos_16)
    endtry
    call setpos('.', l:__newpos_17)
    " )
    call s:token_forward()
    let token = s:text_between(getpos('.'), l:__origpos_18)
    call s:token_backward()
    call s:token_forward()
    " }}} endof generated code
    return {'token': token}
endfunction

function g:PT()
    return s:parse_assignment_from_inside()
endfunction


""""""""""""""""""""""""""""""""""""""""""""""""
" Help functions.
""""""""""""""""""""""""""""""""""""""""""""""""

" returns 0 if position of cursor is changed since last typifization
"           or if line under cursor is changed
" returns 1 otherwise
function s:nothing_changed_since_last_typifization()
    if len(s:type_suggest) <= s:type_suggest_index
        return 0
    end

    let last_suggest = s:type_suggest[s:type_suggest_index]
    let curpos = getpos('.')
    let curline = getline('.')
    if curpos == last_suggest.pos && curline == last_suggest.line
        return 1
    else
        return 0
    endif
endfunction

function s:newsuggest(line, pos)
    return {'line':a:line, 'pos':a:pos}
endfunction

" returns a text between 2 cursor positions,
" lines are joined with optional argument separator.
" default separator is ' '
function s:text_between(pos1, pos2, ...)
    if a:0 == 0
        let separator = ' '
    elseif a:0 == 1
        let separator = a:1
    else
        throw 'value error'
    endif

    let l:line1 = a:pos1[1]
    let l:line2 = a:pos2[1]
    let l:col1 = a:pos1[2] - 1
    let l:col2 = a:pos2[2] - 1

    let l:lines = getline(l:line1, l:line2)
    let l:lines[-1] = l:lines[-1][ : l:col2]
    let l:lines[0] = l:lines[0][l:col1 : ]
    return join(l:lines, separator)
endfunction

" get byte under cursor
function s:current_char()
    let pos = getpos('.')
    return getline(pos[1])[pos[2] - 1]
endfunction

" comapre 2 positions
function s:cmppos(pos1, pos2)
    if a:pos1[0] != a:pos2[0]
        " comparing positions in different bufers
        throw 'value error'
    elseif a:pos1[1] > a:pos2[1]
        return 1
    elseif a:pos1[1] < a:pos2[1]
        return -1
    elseif a:pos1[2] > a:pos2[2]
        return 1
    elseif a:pos1[2] < a:pos2[2]
        return -1
    else
        return 0
    endif
endfunction

function s:printlinetillpos()
    echo "'" . getline('.')[:getpos('.')[2] - 1] . "'"
endfunction

function s:normalize(text)
    let text = a:text
    let text = substitute(text, '\s\+\(\W\)', ' \1', 'g')
    let text = substitute(text, '\(\W\)\s\+', '\1 ', 'g')
    let text = substitute(text, '\s\+$)', '', 'g')
    let text = substitute(text, '^\s\+', '', 'g')
    let text = substitute(text, '>>', '> >', 'g')
    let text = substitute(text, '<<', '< <', 'g')
    return text
endfunction
