" Vim Omni Completion For The Bourne-Shell Scripting Languages.
" Copyright (c) 2020 Sebastian Gniazdowski.
" License: Gnu GPL v3.
" 
" If using an autocomplete plugin and undecided which one to use, then the
" plugin zphere-zsh/shell-autopop-menu is recommended. It'll integrate nicely
" with this plugin as it is specifically tested and adapted to work with it.
" It started as a (fork-based) companion plugin for this omni completion.
" 
" This plugin does no more than setting `omnifunc` (or `completefunc` — see
" below) and `completeopt` set variables, what allows to invoke the completion
" via Ctrl-X Ctrl-O (or Ctrl-X Ctrl-U, see g:zoc_use_cfu_setting below). You may
" want to use g:zoc_auto_insert if using this plugin this way, see below.
"
" 
" 
" Configuration Variables:
" ------------------------
"
" — g:zoc_use_cfu_setting — whether to use completefunc (^X^U) instead of
"   omnifunc (^X^O) setting (default: 0), example:
"       let g:zoc_use_cfu_setting = 1
"
" — g:zoc_search_in_let — whether to search for variables in "let …"
"   statements (slows down a bit, however it allows to complete local variables
"   even when they're used without the l:… prefix) (default: 0), example:
"       let g:zoc_search_in_let = 1
"
" — g:zoc_auto_insert — whether to enable inserting of the first candidate on
"   the activation of the completion on ^X^O — it'll normally only be selected
"   and the buffer/the text will remain unchanged after pressing the keys.
"

" FUNCTION: ZshOmniComplBufInit()
" A function that's called when the buffer is loaded and its filetype is known.
" It initializes the omni completion for the buffer.
function ZshOmniComplBufInit()
    let b:zoc_call_count = 0
    let b:zoc_last_all_lines_get_count = -1
    let b:zoc_cache_lines_active = 0
    let b:zoc_last_completed_line = ''
    let [ b:zoc_last_fccount, b:zoc_last_pccount, 
                \ b:zoc_last_kccount, b:zoc_last_lccount ] = [ [-1], [-1], [-1], [-1] ]
    let b:zoc_last_ccount_vars = [ b:zoc_last_fccount, b:zoc_last_pccount, 
                \ b:zoc_last_kccount, b:zoc_last_lccount ]
    if &ft == 'zsh' || &ft == 'bash' || &ft == 'sh'
        if ! get(g:,'zoc_use_cfu_setting','0')
            setlocal omnifunc=ZshComplete
        else
            setlocal completefunc=ZshComplete
        endif
        setlocal completeopt=menuone,noinsert
        " Ensure the first-item selection is enabled (paranoid).
        setlocal completeopt-=noselect
        "if g:zoc_auto_insert
        "endif
        if get(g:, 'zoc_auto_insert', 0)
            setlocal completeopt-=noinsert
        endif
        call add(g:zoc_zsh_buffers, bufnr())
    endif
endfunction

" FUNCTION: ZshComplete()
" The main function of this plugin (assigned to the `omnifunc` set option) that
" has the main task to perform the omni-completion, i.e.: to return the list of
" matches to the text before the cursor.
function ZshComplete(findstart, base)
    if getline(".") =~ '\v^[[:space:]]*\#.*'
        return -3
    endif
    " Prepare the buffers' contents for processing, if needed (i.e.: on every
    " N-th call, when only also the processing-sequence is being initiated).
    "
    " The update of this buffer-lines cache is synchronized with the other
    " processings, i.e.: it depends on the local (to the buffer) call count
    " of the plugin, however the storage variable is s: -session, to limit the
    " memory usage.
    if b:zoc_call_count % 5 == 0 && b:zoc_last_all_lines_get_count != b:zoc_call_count
        let b:zoc_last_all_lines_get_count = b:zoc_call_count
        let s:zoc_all_buffers_lines = []
        for bufnum in g:zoc_zsh_buffers
            if buflisted(bufnum)
                "echom "Appending of" bufnum b:zoc_call_count
                let s:zoc_all_buffers_lines += map(getbufline(bufnum, 1,"$"), 'substitute(v:val,''\v^[[:space:]]*'', '''', '''')')
            endif
        endfor
    endif

    if a:findstart
        let got_winner = 0
        call CompleteZshFunctions(1, a:base)
        if b:zoc_compl_functions_start >= 0
            let result_compl = CompleteZshFunctions(0, a:base)
            "echom '1/len(result_compl)='.len(result_compl)
            if len(result_compl)
                let result = b:zoc_compl_functions_start
                let winner = 0
                let got_winner = 1
                let to_declare = [ "zoc_compl_parameters_start",
                            \ "zoc_compl_arrays_keys_start",
                            \ "zoc_compl_lines_start" ]
                for var in to_declare | let b:[var] = -3 | endfor
            endif
        endif
        if ! got_winner
            call ZshCompleteLines(1, a:base)
            if ( b:zoc_compl_lines_start >= 0 )
                let result_compl = ZshCompleteLines(0, a:base)
                "echom '2/len(result_compl)='.len(result_compl)
                if len(result_compl)
                    let result = b:zoc_compl_lines_start
                    let winner = 3
                    let got_winner = 1
                    let to_declare = [ "zoc_compl_functions_start",
                                \ "zoc_compl_parameters_start",
                                \ "zoc_compl_arrays_keys_start" ]
                    for var in to_declare | let b:[var] = -3 | endfor
                endif
            endif
        endif
        if ! got_winner 
            let four_results = [ b:zoc_compl_functions_start,
                        \ CompleteZshParameters(1, a:base),
                        \ CompleteZshArrayAndHashKeys(1, a:base),
                        \ ZshCompleteLines(1, a:base) ]
            let result = max( four_results )
            let winner = index( four_results, result )
        endif
        " Restart the cyclic renewal of the database variables from the point
        " where the specific object-kind completion finished the cycle in the
        " previous call to ZshComplete.
        let b:zoc_call_count = (b:zoc_last_ccount_vars[winner])[0] + 1
        "echom "Returning: " . string(result)
    else
        let result = []

        let four_results = [ b:zoc_compl_functions_start,
                    \ b:zoc_compl_parameters_start,
                    \ b:zoc_compl_arrays_keys_start,
                    \ b:zoc_compl_lines_start ]

        for id in range(4)
            if four_results[id] < 0 | continue | endif
            let b:zoc_last_ccount_vars[id][0] = b:zoc_call_count
            let result_im = s:completerFunctions[id](0, a:base)
            if id == g:ZOC_LINE && len(result_im)
                let result = result_im
                break
            endif
            let result += result_im
        endfor
        call uniq(sort(result))
    endif
    return result
endfunction

" FUNCTION: CompleteZshFunctions()
" The function is a complete-function which returns matching Zsh-function names.
function CompleteZshFunctions(findstart, base)
    let [line_bits,line] = s:getPrecedingBits(a:findstart)
    " First call — basically return 0. Additionally (it's unused value),
    " remember the current column.
    if a:findstart
        let line_bits_ne = Filtered(function('len'), line_bits)
        "echom string(line_bits) . string(line_bits_ne)
        "echom "::: FUNS ::: " . string(line_bits) . string(line_bits_ne)
        if len(line_bits_ne)
            let idx = strridx( line, len(line_bits_ne) >= 2 ? line_bits_ne[-2] : line_bits_ne[-1] )
        else
            let idx = 0
        endif
        "echom idx . "← idx"
        if line_bits[-1] !~ '\v\k{1,}$'
            "echom "-3 ← first"
            let b:zoc_compl_functions_start = -3
        elseif len(line_bits_ne) >= 2 && line[idx:] !~ '\v^.*(\|\||\||\&|\&\&|;|exec|nocorrect|noglob|pkexec|while|until|if|then|elif|else|do|time|coproc|\|\&|\&\!|\&\|\()[[:space:]]+\k{1,}$'
            "echom "-3 ← second"
            let b:zoc_compl_functions_start = -3
        else
            let b:zoc_compl_functions_start = strridx(line, line_bits[-1])
            " Support the from-void text completing. It's however disabled on
            " the upper level.
            let b:zoc_compl_functions_start += line_bits[-1] =~ '^[[:space:]]$' ? 1 : 0
        endif
        "echom 'b:zoc_compl_functions_start:' . b:zoc_compl_functions_start
        return b:zoc_compl_functions_start
    else
        " Detect the matching Zsh function names and return them.
        return s:completeKeywords(g:ZOC_FUNC, line_bits, line)
    endif
endfunction

" FUNCTION: CompleteZshParameters()
" The function is a complete-function which returns matching Zsh-parameter names.
function CompleteZshParameters(findstart, base)
    let [line_bits,line] = s:getPrecedingBits(a:findstart)

    " First call — basically return 0. Additionally (it's unused value),
    " remember the current column.
    if a:findstart
        if line_bits[-1] !~ '\v(\$|^[a-zA-Z0-9_]+$)'
            let b:zoc_compl_parameters_start = -3
        else
            let b:zoc_compl_parameters_start = strridx(line, line_bits[-1])
            let idx = stridx(line[b:zoc_compl_parameters_start:],'$')
            let b:zoc_compl_parameters_start = b:zoc_compl_parameters_start + (idx < 0 ? 0 : idx)
            " Support the from-void text completing. It's however disabled on
            " the upper level.
            let b:zoc_compl_parameters_start += line_bits[-1] =~ '^[[:space:]]$' ? 1 : 0
        endif
        "echom 'b:zoc_compl_parameters_start:' . b:zoc_compl_parameters_start
        return b:zoc_compl_parameters_start
    else
        " Detect the matching Zsh parameter names and return them.
        return s:completeKeywords(g:ZOC_PARAM, line_bits, line)
    endif
endfunction

" FUNCTION: CompleteZshArrayAndHashKeys()
" The function is a complete-function which returns matching Zsh-parameter names.
function CompleteZshArrayAndHashKeys(findstart, base)
    let [line_bits,line] = s:getPrecedingBits(a:findstart)

    " First call — basically return 0. Additionally (it's unused value),
    " remember the current column.
    if a:findstart
        if line_bits[-1] !~ '\v[a-zA-Z0-9_]+\['
            let b:zoc_compl_arrays_keys_start = -3
        else
            let b:zoc_compl_arrays_keys_start = strridx(line, line_bits[-1])
            let b:zoc_compl_arrays_keys_start = b:zoc_compl_arrays_keys_start + stridx(line[b:zoc_compl_arrays_keys_start:],'[') + 1
            " Support the from-void text completing. It's however disabled on
            " the upper level.
            let b:zoc_compl_arrays_keys_start += line_bits[-1] =~ '^[[:space:]]$' ? 1 : 0
        endif
        "echom 'b:zoc_compl_arrays_keys_start:' . b:zoc_compl_arrays_keys_start
        return b:zoc_compl_arrays_keys_start
    else
        " Detect the matching arrays' and hashes' keys and return them.
        return s:completeKeywords(g:ZOC_KEY, line_bits, line)
    endif
endfunction

" FUNCTION: ZshCompleteLines()
" The function is a complete-function which returns matching lines.
function ZshCompleteLines(findstart, base)
    let [line_bits,line] = s:getPrecedingBits(a:findstart)

    " First call — basically return 0. Additionally (it's unused value),
    " remember the current column.
    if a:findstart
        " Remember the entry cache-state to verify its change later.
        let enter_cstate = b:zoc_cache_lines_active
        " Line was enriched, extended? Thus, it cannot yield any NEW ↔ DIFFERENT
        " results?
        if len(line) >= len(b:zoc_last_completed_line) && !empty(b:zoc_last_completed_line)
            " Disable the cache invalidation IF a fresh cache has been computed.
            " — 2 — got a fresh cache, invalidation stopped,
            " — -1 — request a fresh cache recomputation before the stop.
            let b:zoc_cache_lines_active = b:zoc_cache_lines_active == 2 ? 2 : -1
        else
            let b:zoc_cache_lines_active = 0
        endif
        "echom (len(line) >= len(b:zoc_last_completed_line) ? "NO, not withdrawed >= (new is longer / same)" : "YES, withdrawed < (new is shorter)") . " →→ " . line . ' ↔ ' . b:zoc_last_completed_line 
        "echom "b:ZOC_CACHE_LINES_ACTIVE ←← " . b:zoc_cache_lines_active
        let b:zoc_last_completed_line = line
        let quoted_stripped = ZshQuoteRegex(substitute(line,'\v^[[:space:]]+', "", ""))
        " A short-path (also a logic- short-path ↔ see the first completer
        " function call) for the locked-in-cache state.
        if b:zoc_cache_lines_active == 2 &&
                \ enter_cstate == 2 &&
                \ empty( matchstr( b:zoc_lines_cache, '\v^'.quoted_stripped.'.*' ) )
            "echom 'CLOSE-PATH (2==2) … →→ 1…2: →→ ' . string(b:zoc_lines_cache[0:1]) . '→→' . matchstr( b:zoc_lines_cache, '\v^'.quoted_stripped.'.*' )
            let b:zoc_compl_lines_start = -3
            "echom '1/b:zoc_compl_lines_start:' . b:zoc_compl_lines_start
            return b:zoc_compl_lines_start
        endif
        if line =~ '\v^[[:space:]]*$'
            "echom "returning -3 here… " . string(line) . '/' b:zoc_last_completed_line
            let b:zoc_compl_lines_start = -3
        else
            let line_bits_ne = Filtered(function('len'), line_bits)
            let idx = stridx(line,line_bits_ne[0])
            let b:zoc_compl_lines_start = idx <= 0 ? 0 : idx
        endif
        "echom '2/b:zoc_compl_lines_start:' . b:zoc_compl_lines_start
        return b:zoc_compl_lines_start
    else
        " Detect the matching arrays' and hashes' keys and return them.
        if b:zoc_cache_lines_active > 0
            "echom 'FROM CACHE [' . b:zoc_cache_lines_active . '], 1…2: → ' . string(b:zoc_lines_cache[0:1])
            let b:zoc_cache_lines_active = b:zoc_cache_lines_active == 2 ? 2 : 0
            if !pumvisible()
                let line2 = VimQuoteRegex(substitute(line, '\v^[[:space:]]+',"",""))
                "echom 'RETURNING FILTERED: ' . string(Filtered2(function('DoesLineMatch'), b:zoc_lines_cache, line2)[0:1])
                return Filtered2 ( function('DoesLineMatch'), b:zoc_lines_cache, line2 )
            else
                return b:zoc_lines_cache
            endif
        else
            " helper var
            let enter_cstate = b:zoc_cache_lines_active
            let b:zoc_cache_lines_active = b:zoc_cache_lines_active == -1 ? 2 : 1
            let b:zoc_lines_cache = s:completeKeywords(g:ZOC_LINE, line_bits, line)
            "echom 'FROM COMPUTATION [' . enter_cstate . '], 1…2: → ' . string(b:zoc_lines_cache[0:1])
            return b:zoc_lines_cache
        endif
    endif
endfunction

"""""""""""""""""" PRIVATE FUNCTIONS

" FUNCTION: s:completeKeywords()
" A general-purpose, variadic backend function, which obtains the request on the
" type of the keywords (functions, parameters or array keys) to complete and
" performs the operation.
function s:completeKeywords(id, line_bits, line)
    let entry_time = reltime()
    " Retrieve the complete list of Zsh functions in the buffer on every
    " N-th call.
    if (b:zoc_call_count == 0) || ((b:zoc_call_count - a:id + 2) % 10 == 0)
        "echom 'CALL: ' . b:zoc_call_count . ' - ' . a:id . ' + 2 % 10 == ' . ((b:zoc_call_count - a:id + 2) % 10)
        call s:gatherFunctions[a:id]()
    endif

    " Ensure that the buffer-variables exist
    let to_declare = filter([ "zoc_functions", "zoc_parameters", "zoc_array_and_hash_keys" ], '!exists("b:".v:val)')
    for bufvar in to_declare | let b:[bufvar] = [] | endfor
    let gatherVariables = [ b:zoc_functions, b:zoc_parameters, 
                \ b:zoc_array_and_hash_keys, s:zoc_all_buffers_lines ]

    " Detect the matching Zsh-object names and store them for returning.
    let result = []
    let a:line_bits[-1] = a:line_bits[-1] =~ '^[[:space:]]$' ? '' : a:line_bits[-1]

    "echom a:id . g:ZOC_PARAM . ' / '. a:line_bits[-1]
    if a:id == g:ZOC_PARAM && a:line_bits[-1] =~ '\v^\$.*'
        let a:line_bits[-1] = (a:line_bits[-1])[1:]
        let pfx='$'
    elseif a:id == g:ZOC_KEY && a:line_bits[-1] =~ '\v^[^\[]+\['
        let a:line_bits[-1] = substitute( a:line_bits[-1], '\v^[^\[]+\[', '', '' )
        let pfx=''
    elseif a:id == g:ZOC_LINE
        let a:line_bits[-1] = substitute(a:line,'\v^[[:space:]]*', '', '')
        let pfx=''
    else
        let pfx=''
    endif
    "echom 'After: '.a:id.' / '.string(a:line_bits)


    let quoted = VimQuoteRegex(a:line_bits[-1])
    "echom "VimQuoteRegex(a:line_bits[-1]): " . quoted
    if a:id == g:VCHRD_LINE
        let result = filter(copy(gatherVariables[a:id]),
                    \ 'v:val =~# ''\v^''.quoted && v:val != a:line_bits[-1]')
    else
        let result = filter(copy(gatherVariables[a:id]),
                    \ 'v:val =~# ''\v^''.quoted')
    endif
    if !empty(pfx)
        call map(result, "pfx . v:val")
    endif

    let g:zoc_summaric_completion_time += reltimefloat(reltime(entry_time))
    "echohl WarningMsg
    "echom "⟁⟁⟁ ckeywords ⟁⟁⟁  ·•««" a:id "»»•·  ∞ elapsed-time ∞  ≈≈≈" split(reltimestr(reltime(entry_time)))[0]
    "echohl None

    return result
endfunction

" FUNCTION: s:gatherFunctionNames()
" Buffer-contents processor for Zsh *function* names. Stores all the detected
" Zsh function names in the list b:zoc_parameters.
function s:gatherFunctionNames()
    " Prepare, i.e.: zero the buffer collection-variable.
    let b:zoc_functions = []

    " First gather the proper lines of the buffers.
    let b:zoc_functions = filter(copy(s:zoc_all_buffers_lines), 'v:val =~# ''\v^[[:space:]]*fu%[nction][[:space:]]*\!=[[:space:]]+([^[:space:]]+)[[:space:]]*\(''')
    " Then extract the function names.
    call map( b:zoc_functions, 'matchlist(v:val, ''\v^[[:space:]]*fu%[nction][[:space:]]*\!=[[:space:]]+([^[:space:]]+)[[:space:]]*\('')[1]' )
    " Uniqify the resulting list of Vim function names. The uniquification
    " requires also sorting the input list.
    call uniq(sort(b:zoc_functions))
endfunction

" FUNCTION: s:gatherParameterNames()
" Buffer-contents processor for Zsh *parameter* names. Stores all the detected
" Zsh parameter names in the list b:zoc_parameters.
function s:gatherParameterNames()
    let b:zoc_parameters = filter(copy(s:zoc_all_buffers_lines), 'v:val =~# ''\v\$(\{|)([#+^=~]{1,2}){0,1}(\([a-zA-Z0-9_:@%.\|;#~]+\)){0,1}#{0,1}[a-zA-Z0-9_]+''')
    call map(b:zoc_parameters,'substitute(v:val, ''\v.*\$(\{|)([#+^=~]{1,2}){0,1}(\([a-zA-Z0-9_:@%.\|;#~]+\)){0,1}#{0,1}([a-zA-Z0-9_]+).*'',''\4'',"g")')

    " Uniqify the resulting list of Zsh parameter names. The uniquification
    " requires also sorting the input list.
    call uniq(sort(b:zoc_parameters))
endfunction

" FUNCTION: s:gatherArrayAndHashKeys()
" Buffer-contents processor for Zsh *parameter* names. Stores all the detected
" Zsh parameter names in the list b:zoc_parameters.
function s:gatherArrayAndHashKeys()
    " Prepare/zero the buffer variable.
    let b:zoc_array_and_hash_keys = []

    " Iterate over the lines in the buffer searching for a Zsh parameter name.
    for line in s:zoc_all_buffers_lines
        let idx=0
        let idx = match(line, '\v[a-zA-Z0-9_]+\[[^\]]+\]', idx)
        while idx >= 0
            let res_list = matchlist(line, '\v[a-zA-Z0-9_]+\[([^\]]+)\]', idx)
            call add(b:zoc_array_and_hash_keys, res_list[1])
            let idx = match(line, '\v[a-zA-Z0-9_]+\[[^\]]+\]', idx+len(res_list[1])+2)
        endwhile
    endfor

    " Uniqify the resulting list of Zsh parameter names. The uniquification
    " requires also sorting the input list.
    call uniq(sort(b:zoc_array_and_hash_keys))
endfunction

" FUNCTION: s:gatherLines()
" Buffer-contents processor for Zsh *parameter* names. Stores all the detected
" Zsh parameter names in the list b:zoc_parameters.
function s:gatherLines()
endfunction

" FUNCTION: ZshQuoteRegex()
" A function which quotes the regex-special characters with a backslash, which
" makes them inactive, literal characters in the very-magic mode (… =~ " '\v…').
function ZshQuoteRegex(str)
    return substitute( a:str, '\v[^0-9A-Za-z_[:space:]]','\\&',"g" )
endfunction

" The idea of this completion plugin is the following:
" - SomeTextSomeText SomeOtherText
"   ……………………↑ <the cursor>.
" What will be completed, will be:
" - the matching keywords (functions, parameters, etc.) that match:
"   SomeTextSomeText,
" - so the completion takes the whole part in which the cursor currently is
"   being located, not only the preceding part.
function s:getPrecedingBits(findstart)
    if a:findstart
        let line = getbufline(bufnr(), line("."))[0]
        let b:zoc_curline = line
        let curs_col = col(".")
        let b:zoc_cursor_col = curs_col
    else
        let line = b:zoc_curline
        let curs_col = b:zoc_cursor_col
    endif

    let line_bits = split(line,'\v[[:space:]\{\}\(\)\#\%\=\^\!\*\<\>]')
    let line_bits = len(line_bits) >= 1 ? line_bits : [len(line) > 0 ? (line)[len(line)-1] : ""]

    if len(line_bits) > 1
        " Locate the *active*, *hot* bit in which the cursor is being placed.
        let l:count = len(line_bits)
        let work_line = line
        for bit in reverse(copy(line_bits))
            let idx = strridx(work_line, bit)
            if idx <= curs_col - 2
                " Return a sublist with the preceding elements up to the active,
                " *hot* bit.
                return [line_bits[0:l:count], line]
            endif
            let work_line = work_line[0:idx-1]
            let l:count -= 1
        endfor
    endif
    return [line_bits, line]
endfunction

"""""""""""""""""" THE SCRIPT BODY

let s:gatherFunctions = [ function("s:gatherFunctionNames"),
            \ function("s:gatherParameterNames"),
            \ function("s:gatherArrayAndHashKeys"),
            \ function("s:gatherLines") ]

let s:completerFunctions = [ function("CompleteZshFunctions"),
            \ function("CompleteZshParameters"),
            \ function("CompleteZshArrayAndHashKeys"),
            \ function("ZshCompleteLines") ]

augroup ZshOmniComplInitGroup
    au FileType * call ZshOmniComplBufInit()
augroup END

let [ g:ZOC_FUNC, g:ZOC_PARAM, g:ZOC_KEY, g:ZOC_LINE ] = [ 0, 1, 2, 3 ]
let g:zoc_zsh_buffers = []
let g:zoc_summaric_completion_time = 0.0
let g:shell_omni_completion_loaded = 1

"""""""""""""""""" UTILITY FUNCTIONS

function! Mapped(fn, l)
    let new_list = deepcopy(a:l)
    call map(new_list, string(a:fn) . '(v:val)')
    return new_list
endfunction

function! Filtered(fn, l)
    let new_list = deepcopy(a:l)
    call filter(new_list, string(a:fn) . '(v:val)')
    return new_list
endfunction

function! Filtered2(fn, l, arg)
    let new_list = deepcopy(a:l)
    "echom "Filtered2 [len:".len(new_list)."]:" string(a:fn).'(v:val, "' . substitute(a:arg,'\v([\"\\])','\\\1',"g") . '")'
    call filter(new_list, string(a:fn).'(v:val, "' . substitute(a:arg,'\v([\"\\])','\\\1',"g") . '")')
    return new_list
endfunction

function! FilteredNot(fn, l)
    let new_list = deepcopy(a:l)
    call filter(new_list, '!'.string(a:fn) . '(v:val)')
    return new_list
endfunction

function! DoesLineMatch(match, line)
    return a:match =~# '\v^' . a:line . '.*'
endfunction

function! CreateEmptyList(name)
    eval("let ".a:name." = []")
endfunction

function! FunConcat(f, ...)
    return a:f."('".join(a:000, "', '")."')"
endfunction
" vim:set ft=vim tw=80 et sw=4 sts=4 foldmethod=marker:
