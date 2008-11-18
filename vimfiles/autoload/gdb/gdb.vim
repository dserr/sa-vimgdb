" ==============================================================================
" File          : gdb.vim
" Author        : Srinath Avadhanula <srinathava AT google's email service>
" Description   :
" ============================================================================== 

" Do not want to re-source this file because then the state stored in the
" script-local variables gets trashed.
if exists('s:doneSourcingFile')
    finish
endif
let s:doneSourcingFile = 1

" ==============================================================================
" User preferences
" ============================================================================== 
" gdb#gdb#Let: safely assign to a variable {{{
" Description: 
function! gdb#gdb#Let(varName, value)
    if !exists('g:'.a:varName)
        let g:{a:varName} = a:value
    endif
endfunction " }}}
call gdb#gdb#Let('GdbCmdWinName', '_GDB_Command_Window_')
call gdb#gdb#Let('GdbStackWinName', '_GDB_Stack_Window_')
call gdb#gdb#Let('GdbShowAsyncOutputWindow', 1)

" ==============================================================================
" Script local variables
" ============================================================================== 
let s:userIsBusy = 0
let s:gdbStarted = 0
let s:scriptDir = expand('<sfile>:p:h')

let s:GdbCmdWinName = g:GdbCmdWinName
let s:GdbStackWinName = g:GdbStackWinName

let s:GdbCmdWinBufNum = -1
let s:GdbStackWinBufNum = -1

let s:userMappings = {}

" s:GdbInitWork: does the actual work of initialization {{{
" Description: 
function! s:GdbInitWork( )
    " Cannot start multiple GDB sessions from a single VIM session.
    if s:gdbStarted == 1
        echohl Search
        echomsg "Gdb is busy. Interrupt the program or try again later."
        echohl None
        return
    endif

    let s:gdbStarted = 1
    let s:GdbCmdWinBufNum = s:GdbOpenWindow(s:GdbCmdWinName)
    setlocal filetype=gdbvim

    " Start the GDBMI server...
    " exec '!python '.s:scriptDir.'/VimGdbServer.py '.v:servername.' > /dev/null &'
    exec '!xterm -e python '.s:scriptDir.'/VimGdbServer.py '.v:servername.' &'
    exec '!sleep 0.4'

    python import sys
    exec 'python sys.path += [r"'.s:scriptDir.'"]'

    " python from VimGdbServer import startVimServerThread
    " exec 'python startVimServerThread("'.v:servername.'")'
    " !sleep 0.4

    python from VimGdbClient import VimGdbClient
    exec 'python gdbClient = VimGdbClient('.s:GdbCmdWinBufNum.')'

    " prevent stupid press <return> to continue prompts.
    call gdb#gdb#RunCommand('set height 0')

    augroup TerminateGdb
        au!
        au VimLeavePre * :call gdb#gdb#Terminate()
    augroup END

    augroup MarkGdbUserBusy
        au!
        au CursorMoved  * :let s:userIsBusy = 1
        au CursorMovedI * :let s:userIsBusy = 1
        au CmdWinEnter  * :let s:userIsBusy = 1

        au CursorHold   * :let s:userIsBusy = 0
        au CursorHoldI  * :let s:userIsBusy = 0
        au CmdWinLeave  * :let s:userIsBusy = 0
    augroup END

    set balloonexpr=gdb#gdb#BalloonExpr()
    set ballooneval
    set balloondelay=500
    set updatetime=500

    call s:CreateGdbMaps()

    wincmd w
endfunction " }}}
" gdb#gdb#Init: {{{
function! gdb#gdb#Init()
    keepalt call s:GdbInitWork()
endfunction " }}}
" s:GdbOpenWindow: opens one of the GDB windows {{{

let s:gdbBufNums = {}
function! s:GdbOpenWindow(bufName)
    let bufnum = bufnr(a:bufName, 1)
    let s:gdbBufNums[bufnum] = 1

    let winnum = bufwinnr(bufnum)
    if winnum != -1
        exec winnum.' wincmd w'
    else
        for n in keys(s:gdbBufNums)
            " the bizzare dual nature of Vim's data types. Yuck!
            let winnum = bufwinnr(n+0)
            if winnum != -1
                exec winnum.' wincmd w'
                exec 'vert split '.a:bufName
                break
            endif
        endfor
        if winnum == -1
            exec 'top split #'.bufnum
        endif
    endif

    call setbufvar(bufnum, '&swapfile', 0)
    call setbufvar(bufnum, '&buflisted', 0)
    call setbufvar(bufnum, '&buftype', 'nofile')
    call setbufvar(bufnum, '&ts', 8)

    resize 10
    return bufnum
endfunction " }}}
" s:CreateMap: creates a map safely {{{
" Description: 
function! s:CreateMap(key, rhs, mode)
    let s:userMappings[a:mode . a:key] = maparg(a:key, a:mode)
    exec a:mode.'map <silent> '.a:key.' '.a:rhs
endfunction " }}}
" s:RestoreUserMaps: restores user mappings {{{
" Description: 
function! s:RestoreUserMaps()
    for item in keys(s:userMappings)
        let mode = item[0]
        let lhs = item[1:]
        let rhs = s:userMappings[item]
        if rhs != ''
            exec mode.'map <silent> '.lhs.' '.rhs
        else
            exec mode.'unmap '.lhs
        endif
    endfor
endfunction " }}}
" s:CreateGdbMaps: creates GDB specific mappings {{{
" Description: 
function! s:CreateGdbMaps()
    call s:CreateMap('<C-c>',   ':call gdb#gdb#Interrupt()<CR>', 'n')
    call s:CreateMap('<F5>',    ':call gdb#gdb#RunOrContinue()<CR>', 'n')
    call s:CreateMap('<S-F5>',  ':call gdb#gdb#Kill()<CR>', 'n')
    call s:CreateMap('<C-F5>',  ':call gdb#gdb#Interrupt()<CR>', 'n')
    call s:CreateMap('<F10>',   ':call gdb#gdb#Next()<CR>', 'n')
    call s:CreateMap('<F11>',   ':call gdb#gdb#Step()<CR>', 'n')
    call s:CreateMap('<S-F11>', ':call gdb#gdb#Finish()<CR>', 'n')
    call s:CreateMap('U',       ':call gdb#gdb#FrameUp()<CR>', 'n')
    call s:CreateMap('D',       ':call gdb#gdb#FrameDown()<CR>', 'n')
    call s:CreateMap('<F9>',    ':call gdb#gdb#ToggleBreakPoint()<CR>', 'n')
    call s:CreateMap('<C-P>',   ':call gdb#gdb#PrintExpr()<CR>', 'n')
    call s:CreateMap('<C-P>',   'y:call gdb#gdb#RunCommand("print <C-R>"")<CR>', 'v')
endfunction " }}}

" ==============================================================================
" Updating the _GDB_ window dynamically. {{{
" 
" There are a LOT of hacks in order to accomplish dynamically updating the
" GDB output window via a thread spawned off by the main thread. When we
" are waiting for control to return to the VIM window, we start off a
" thread which waits for the string '*done' to be printed out by GDB.
" However, the output generated in the meanwhile still needs to appear. If
" we do this by drawing commands in the thread, then async errors happen.
" Therefore there is a lot of going back and forth. The basic idea is that
" the child thread "feedkeys" to the main thread which then handles updates
" to the UI.
" }}}
" ============================================================================== 
" gdb#gdb#IsUserBusy: returns 1 if cursor moved etc. {{{
" Description: 
function! gdb#gdb#IsUserBusy()
    return s:userIsBusy || mode() != 'n'
endfunction " }}}
" gdb#gdb#UpdateCmdWin: {{{
function! gdb#gdb#UpdateCmdWin()
    " This function gets called by the thread which is monitoring for
    " control to get back to the GDB process. This is called when the
    " program is still running but GDB has produced some output.

    " If the Gdb command window is not open, don't do anything.
    if bufwinnr(s:GdbCmdWinBufNum) == -1
        return
    endif

    python gdbClient.printme()
    redraw
endfunction " }}}
" gdb#gdb#ScrollCmdWin: {{{
function! gdb#gdb#ScrollCmdWin(gdbWinName)
    let gdbWinNr = bufwinnr(a:gdbWinName)
    if gdbWinNr == -1
        return
    endif
    let presWinNr = winnr()

    if gdbWinNr != presWinNr
        exec gdbWinNr.' wincmd w'
    endif
    normal! G
    if gdbWinNr != presWinNr
        wincmd w
    endif
    redraw
endfunction " }}}
" gdb#gdb#OnResume: {{{
function! gdb#gdb#OnResume()
    " This function gets called when the background GDB process regains
    " control and is ready to process commands once again. We should
    " probably just go to the current frame when this happens.
    " call Debug('+gdb#gdb#OnResume', 'gdb')

    set balloonexpr=gdb#gdb#BalloonExpr()

    " We want to make sure that the command window shows the latest stuff
    " when we are given control. Too bad if the user is busy typing
    " something while this is going on.
    " call gdb#gdb#UpdateCmdWin()
    call gdb#gdb#GotoCurFrame()

    let pos = getpos('.')
    let bufnum = bufnr('%')
    call gdb#gdb#ShowStack()
    exec bufwinnr(bufnum).' wincmd w'
    call setpos('.', pos)

    redraw
endfunction " }}}
" gdb#gdb#GetQueryAnswer:  {{{
" Description: 
function! gdb#gdb#GetQueryAnswer()
    python gdbClient.getQueryAnswer()
    return retval
endfunction " }}}

" ==============================================================================
" Miscellaneous GDB commands
" ============================================================================== 
" s:GdbGetCommandOutputSilent: gets the output of the command {{{
" Description: 
function! s:GdbGetCommandOutputSilent(cmd)
    if s:GdbWarnIfBusy()
        return ''
    endif

    python gdbClient.updateWindow = False
    exec 'python gdbClient.getCommandOutput("""'.a:cmd.' """, "retval")'
    python gdbClient.updateWindow = True
    return retval
endfunction " }}}
" s:GdbGetCommandOutput: gets the output of the command {{{
" Description: 
function! s:GdbGetCommandOutput(cmd)
    if s:GdbWarnIfBusy()
        return ''
    endif
    exec 'python gdbClient.getCommandOutput("""'.a:cmd.' """, "retval")'
    return retval
endfunction " }}}
" gdb#gdb#RunCommand: runs the given GDB command {{{
" Description: should only be used to run commands which do not transfer
" control back to the inferior program. Otherwise, the main VIM window
" itself will hang till an interrupt is sent to the inferior.
function! gdb#gdb#RunCommand(cmd)
    if s:GdbWarnIfBusy()
        return
    endif
    if a:cmd == ''
        let cmd = input('Enter GDB command to run: ')
    else
        let cmd = a:cmd
    endif

    exec 'python gdbClient.runCommand("""'.cmd.'""")'
endfunction " }}}
" gdb#gdb#Terminate: terminates the running GDB thread {{{
function! gdb#gdb#Terminate()
    if s:gdbStarted == 1
        python gdbClient.terminate()
        call s:RestoreUserMaps()
        let s:gdbStarted = 0
    end
endfunction " }}}
" gdb#gdb#PlaceSign: places a sign at a given location {{{
" Description:  

let s:currentSignNumber = 1
sign define gdbCurFrame text==> texthl=Search linehl=Search
function! gdb#gdb#PlaceSign(file, lnum)

    " Goto the window showing this file or the first listed buffer.
    let winnum = bufwinnr(a:file)
    if winnum == -1
        " file is not currently being shown
        " find the first listed buffer.
        let i = 1
        while i <= winnr('$')
            if getbufvar(winbufnr(i), '&buflisted') != 0
                let winnum = i
                break
            endif
            let i = i + 1
        endwhile
        if winnum == -1
            " no buffers are listed! Random case, just split open a new
            " window with the file.
            exec 'split '.a:file
        else
            " goto the window showing the first listed buffer and drop the
            " file onto it.
            exec winnum.' wincmd w'
            exec 'drop '.a:file
        endif
    else
        " goto the window showing the file.
        exec winnum.' wincmd w'
    endif

    " Now goto the correct cursor location and place the sign.
    call cursor(a:lnum, 1)
    exec 'sign place 1 name=gdbCurFrame line='.a:lnum.' file='.a:file
endfunction " }}}
" gdb#gdb#IsBusy: tells if inferior program is running {{{
" Description: 
function! gdb#gdb#IsBusy()
    py vim.command('let retval = %s' % gdbClient.isBusy())
    return retval
endfunction " }}}
" s:GdbWarnIfNotStarted: warns if GDB has not been started {{{
" Description:  
function! s:GdbWarnIfNotStarted( )
    if s:gdbStarted == 0
        echohl Error
        echomsg "Gdb is not started. Start it and then run commands"
        echohl None
        return 1
    endif
    return 0
endfunction " }}}
" s:GdbWarnIfBusy: warns if GDB is busy {{{
" Description:  
function! s:GdbWarnIfBusy()
    if s:GdbWarnIfNotStarted()
        return 1
    endif
    if gdb#gdb#IsBusy()
        echohl Search
        echomsg "Gdb is busy. Interrupt the program or try again later."
        echohl None
        return 1
    endif
    return 0
endfunction " }}}
" gdb#gdb#RunOrResume: runs or resumes a GDB command {{{
" Description: This function tries to figure out whether the given command
" returns control back to GDB and if so uses ResumeProgram rather than run.
function! gdb#gdb#RunOrResume(arg)
    if a:arg =~ '^start$'
        call gdb#gdb#Init()
    elseif a:arg =~ '^\(run\|re\%[turn]\|co\%[ntinue]\|fi\%[nish]\|st\%[epi]\|ne\%[xti]\)'
        call gdb#gdb#ResumeProgram(a:arg)
    else
        call gdb#gdb#RunCommand(a:arg)
    endif
endfunction " }}}
" gdb#gdb#SetQueryAnswer: sets an answer for future queries {{{
" Description: 
function! gdb#gdb#SetQueryAnswer(ans)
    if a:ans != ''
        exec 'py gdbClient.queryAnswer = "'.a:ans.'"'
    else
        exec 'py gdbClient.queryAnswer = None'
    endif
endfunction " }}}

" ==============================================================================
" Stack manipulation and information
" ============================================================================== 
" gdb#gdb#GotoCurFrame: places cursor at current frame {{{
" Description: 
function! gdb#gdb#GotoCurFrame()
    if s:GdbWarnIfBusy()
        return
    endif

    sign unplace 1
    python gdbClient.gotoCurrentFrame()
    redraw
endfunction " }}}
" gdb#gdb#FrameUp: goes up the stack (i.e., to caller function) {{{
" Description:  
function! gdb#gdb#FrameUp()
    if s:GdbWarnIfBusy()
        return
    endif

    call gdb#gdb#RunCommand('up')
    call gdb#gdb#GotoCurFrame()
endfunction " }}}
" gdb#gdb#FrameDown: goes up the stack (i.e., to caller function) {{{
" Description:  
function! gdb#gdb#FrameDown()
    if s:GdbWarnIfBusy()
        return
    endif

    call gdb#gdb#RunCommand('down')
    call gdb#gdb#GotoCurFrame()
endfunction " }}}
" gdb#gdb#FrameN: goes to the n^th frame {{{
" Description:  
function! gdb#gdb#FrameN(frameNum)
    if s:GdbWarnIfBusy()
        return
    endif

    if a:frameNum < 0
        let frameNum = input('Enter frame number to go to: ')
    else
        let frameNum = a:frameNum
    endif
    call s:GdbGetCommandOutputSilent('frame '.frameNum)
    call gdb#gdb#GotoCurFrame()
endfunction " }}}
" gdb#gdb#ShowStack: shows current GDB stack {{{
" Description:  

" GotoSelectedFrame: goes to the selected frame {{{
function! <SID>GotoSelectedFrame()
    let frameNum = matchstr(getline('.'), '\d\+')
    if frameNum != ''
        call gdb#gdb#FrameN(frameNum)
    else
        call gdb#gdb#FrameN(-1)
    endif
endfunction " }}}
function! gdb#gdb#ShowStack()
    if s:GdbWarnIfBusy()
        return
    endif

    let s:GdbStackWinBufNum = s:GdbOpenWindow(s:GdbStackWinName)
    " remove original stuff.
    % d _
    let stack = s:GdbGetCommandOutputSilent('bt 10')
    for txt in split(stack, '[\n\r]')
        if txt !~ '' && txt =~ '\S'
            call append(line('$'), txt)
        endif
    endfor
    " delete the first and last lines
    1,2 d _
    $ d _

    setlocal nowrap

    " set up a local map to go to the required frame.
    exec "nmap <buffer> <silent> <CR> :call \<SID>GotoSelectedFrame()<CR>"
endfunction " }}}

" ==============================================================================
" Break-point stuff.
" ============================================================================== 
" gdb#gdb#SetBreakPoint: {{{

let s:numBreakPoints = 0

exec 'sign define gdbBreakPoint text=!! icon='.s:scriptDir.'/bp.png texthl=Error'
function! gdb#gdb#SetBreakPoint()
    call s:SetBreakPointAt(expand('%:p'), line('.'), gdb#gdb#GetAllBreakPoints())
endfunction " }}}
" s:SetBreakPointAt: sets breakpoint at (file, line) {{{
" Description: 
function! s:SetBreakPointAt(fname, lnum, prevBps)
    " To fix very strange problem with setting breakpoints in files on
    " network drives.
    let fnameTail = fnamemodify(a:fname, ':t')
    let output = s:GdbGetCommandOutput('break '.fnameTail.':'.a:lnum)
    if output =~ 'Breakpoint \d\+'
        let bpnum = matchstr(output, 'Breakpoint \zs\d\+')
        let lnum = line('.')
        
        let spec = 'line='.a:lnum.' file='.a:fname

        let idx = index(a:prevBps, spec)
        if idx < 0
            let signId = (1024+s:numBreakPoints)

            " FIXME: Should do this only if a sign is already not placed at
            " this location.
            exec 'sign place '.signId.' name=gdbBreakPoint '.spec
            let s:numBreakPoints += 1
        endif
    endif
endfunction " }}}
" gdb#gdb#ClearBreakPoint: clears break point {{{
" Description:  
function! gdb#gdb#ClearBreakPoint()
    if s:GdbWarnIfBusy()
        return
    endif

    " ask GDB to clear breakpoints here.
    call gdb#gdb#RunCommand('clear '.expand('%:p:t').':'.line('.'))

    let spec = 'line='.line('.').' file='.expand('%:p')
    let breakPoints = gdb#gdb#GetAllBreakPoints()

    while 1
        let again = 0
        try
            " Ideally we would only remove breakpoints set by GDB. But
            " since I use breakpoints only set by us, it doesn't matter.
            sign unplace
            let again = 1
        catch /E159/
            " no more signs in this location
            break
        endtry
    endwhile

endfunction " }}}
" gdb#gdb#GetAllBreakPoints: gets all breakpoints set by us {{{
" Description: 
function! gdb#gdb#GetAllBreakPoints()
    let signs = s:GetCommandOutput('sign place')

    let bps = []
    let fname = ''
    for line in split(signs, '\n')
        if line =~ 'Signs for'
            let fname = matchstr(line, 'Signs for \zs.*\ze:$')
            let fname = fnamemodify(fname, ':p')
        endif
        if line =~ 'name=gdbBreakPoint'
            let lnum = matchstr(line, 'line=\zs\d\+\ze')
            let bps += ['line='.lnum.' file='.fname]
        endif
    endfor

    return bps
endfunction " }}}
" gdb#gdb#RedoAllBreakpoints: refreshes the breakpoints {{{
" Description: 
function! gdb#gdb#RedoAllBreakpoints()
    call gdb#gdb#SetQueryAnswer('y')
    let breakPoints = gdb#gdb#GetAllBreakPoints()
    for bp in breakPoints
        let items = matchlist(bp, 'line=\(\d\+\) file=\(.*\)')
        let line = items[1]
        let fname = items[2]
        call s:SetBreakPointAt(fname, line, breakPoints)
    endfor
    call gdb#gdb#SetQueryAnswer('')
endfunction " }}}
" gdb#gdb#ToggleBreakPoint: toggle breakpoint {{{
" Description: 
function! gdb#gdb#ToggleBreakPoint()
    let signs = s:GetCommandOutput('sign place buffer='.bufnr('%'))
    for line in split(signs, '\n')
        if line =~ 'line='.line('.').'.* name=gdbBreakPoint'
            call gdb#gdb#ClearBreakPoint()
            return
        endif
    endfor
    call gdb#gdb#SetBreakPoint()
endfunction " }}}

" ==============================================================================
" Program execution, stepping, continuing etc.
" ============================================================================== 
" gdb#gdb#Attach: attach to a running program {{{
" Description: 
" s:GetPidFromName: gets the PID from the name of a program {{{
" Description: 
function! s:GetPidFromName(name)
    let ps = system('ps -u '.$USER.' | grep '.a:name)
    if ps == ''
        echohl ErrorMsg
        echo "No running go process found"
        echohl NOne
        return ''
    end

    if ps =~ '\n\s*\d\+'
        echohl ErrorMsg
        echo "Too many running processes. Don't know which to attach to."
        echohl None
        return ''
    end
    return matchstr(ps, '^\s*\zs\d\+')
endfunction " }}}
function! gdb#gdb#Attach(pid)
    let pid = a:pid
    if pid == ''
        let input = input('Enter the PID or process name to attach to :')
        if input =~ '^\d+$'
            let pid = input
        else
            let pid = s:GetPidFromName(input)
            if pid == ''
                return
            end
        endif
    endif
    call gdb#gdb#RunCommand('attach '.pid)
endfunction " }}}
" gdb#gdb#ResumeProgram: gives control back to the inferior program {{{
" Description: This should be used for GDB commands which could potentially
" take a long time to finish.
function! gdb#gdb#ResumeProgram(cmd)
    if s:GdbWarnIfBusy()
        return
    endif
    sign unplace 1
    set balloonexpr=

    exec 'python gdbClient.resumeProgram("""'.a:cmd.'""")'
endfunction " }}}
" gdb#gdb#Run: runs the inferior program {{{
function! gdb#gdb#Run()
    call gdb#gdb#ResumeProgram('run')
endfunction " }}}
" gdb#gdb#Continue: {{{
function! gdb#gdb#Continue()
    call gdb#gdb#ResumeProgram('continue')
endfunction " }}}
" gdb#gdb#RunOrContinue: runs/continues the inferior {{{
" Description: 
function! gdb#gdb#RunOrContinue()
    let output = s:GdbGetCommandOutputSilent('info program')
    if output =~ 'not being run'
        call gdb#gdb#Run()
    else
        call gdb#gdb#Continue()
    endif
endfunction " }}}
" gdb#gdb#Next: {{{
function! gdb#gdb#Next()
    call gdb#gdb#ResumeProgram('next')
endfunction " }}}
" gdb#gdb#Step: {{{
function! gdb#gdb#Step()
    call gdb#gdb#ResumeProgram('step')
endfunction " }}}
" gdb#gdb#Return: {{{
function! gdb#gdb#Return()
    " Should we just do a gdb#gdb#RunCommand here?
    call gdb#gdb#ResumeProgram('return')
endfunction " }}}
" gdb#gdb#Finish: {{{
function! gdb#gdb#Finish()
    call gdb#gdb#ResumeProgram('finish')
endfunction " }}}
" gdb#gdb#Until: runs till cursor position {{{
" Description: 
function! gdb#gdb#Until()
    " we use Resume rather than Run because the program could potentially
    " never reach here.
    call gdb#gdb#ResumeProgram('until '.expand('%:p:t').':'.line('.'))
endfunction " }}}
" gdb#gdb#Interrupt: interrupts the inferior program {{{
function! gdb#gdb#Interrupt( )
    if s:GdbWarnIfNotStarted()
        return
    endif
    python gdbClient.interrupt()
endfunction " }}}
" gdb#gdb#Kill: kills the inferior {{{
function! gdb#gdb#Kill()
    if s:GdbWarnIfNotStarted()
        return
    endif
    if gdb#gdb#IsBusy()
        call gdb#gdb#Interrupt()
    endif
    call gdb#gdb#RunCommand('kill')
    let progInfo = s:GdbGetCommandOutputSilent('info program')
    if progInfo =~ 'is not being run'
        sign unplace 1
        set balloonexpr=
        call gdb#gdb#Terminate()
    endif
endfunction " }}}

" ==============================================================================
" Balloon expression
" ============================================================================== 
" gdb#gdb#BalloonExpr: balloonexpr for GDB {{{
function! gdb#gdb#BalloonExpr()
    if gdb#gdb#IsBusy()
        return ''
    endif
    let str = s:GetContingString(v:beval_bufnr, v:beval_lnum, v:beval_col)
    let eval = s:GdbGetCommandOutputSilent('print '.str)
    let eval =  matchstr(eval, '\$\d\+ = \zs.\{-}\ze\r')
    return str.' = '.eval
endfunction " }}}
" gdb#gdb#PrintExpr: prints the expression under cursor {{{
" Description:  
function! gdb#gdb#PrintExpr()
    let str = s:GetContingString(bufnr('%'), line('.'), col('.'))
    call gdb#gdb#RunCommand('print '.str)
endfunction " }}}
" s:GetContingString: returns the longest chain of struct refs {{{
function! s:GetContingString(bufnr, lnum, col)
    let txtlist = getbufline(a:bufnr, a:lnum)
    if len(txtlist) == 0
        return ''
    endif

    let txt = txtlist[0]
    if txt[a:col-1] !~ '\k'
        return ''
    endif

    let pretxt = strpart(txt, 0, a:col)
    let pretxt = matchstr(pretxt, '\(\w\+\(\(->\)\|\.\)\)*\w\+$')
    let posttxt = strpart(txt, a:col)
    let posttxt = matchstr(posttxt, '^\(\w\+\)')

    let matchtxt = pretxt.posttxt
    return matchtxt
endfunction " }}}

" ==============================================================================
" utils
" ============================================================================== 
" gdb#gdb#GetLocal: returns a local variable {{{
" Description:  
function! gdb#gdb#GetLocal(varname)
    exec 'return s:'.a:varname
endfunction " }}}
" s:GetCommandOutput: gets the output of a vim command {{{
" Description: 
function! s:GetCommandOutput(cmd)
    let _a = @a
    " get a list of all signs
    redir @a
    exec 'silent! '.a:cmd
    redir END
    let output = @a
    let @a = _a

    return output
endfunction " }}}

" vim: fdm=marker
