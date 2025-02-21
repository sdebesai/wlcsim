#include "../defines.inc"
module windowTools
implicit none
contains

function exponential_random_int(window,rand_stat) result(output)
    ! this function gives a random exponentially distributed intiger
    ! the most likely outcome is 0
    use params, only: dp
    use mersenne_twister
    implicit none
    type(random_stat), intent(inout) :: rand_stat  ! status of random number generator
    real(dp) urnd(1) ! single random number
    real(dp), intent(in) :: window
    integer output
    call random_number(urnd,rand_stat)
    output  = nint(-1.0_dp*log(urnd(1)+0.000001_dp)*window+0.0001_dp)
    output = abs(output)
end function exponential_random_int

!Expand [IB1,IB2] and [IT1,IT2] regions to include bound pairs
!Return success=False not able to do this
subroutine enforceBinding(rand_stat,IB1,IB2,IT1,IT2,max_window,success)
! values from wlcsim_data
use params, only: wlc_ExplicitBindingPair, wlc_network_start_index, wlc_other_beads
use params, only: dp
use mersenne_twister
use polydispersity, only: are_on_same_chain, get_IB
implicit none
type(random_stat), intent(inout) :: rand_stat  ! status of random number generator
integer, intent(inout) :: IT1,IT2,IB1,IB2
real(dp), intent(in) :: max_window
logical, intent(out) :: success
integer otherEnd
real(dp) urnd(1) ! single random number
integer IT1_temp, IT2_temp, IB1_temp, IB2_temp, I
logical test_move
integer indx
success = .True.
if (WLC_P__PROB_BIND_RESPECTING_MOVE < 1.0_dp) then
    call random_number(urnd,rand_stat)
    test_move = WLC_P__PROB_BIND_RESPECTING_MOVE > urnd(1)
else
    test_move = .TRUE.
endif
if (test_move) then
    if (WLC_P__NO_LEF_CROSSING) then
        ! IF we can be guarunteed that not loop will cross
        ! attempt to grow region to garuntee no external loops
        if (WLC_P__NETWORK) then
            print*, "NO_LEF_CROSSING is inconsistant with network"
            stop
        endif
        IB1_temp=IB1
        IT1_temp=IT1
        IB2_temp=IB2
        IT2_temp=IT2
        do I =IT1,IT2
            otherEnd=wlc_ExplicitBindingPair(I)
            if (WLC_P__NP>1) then
                ! make sure the other end is on the same polymer
                if (.not. are_on_same_chain(IT1,otherEnd)) then
                    if (WLC_P__PROB_BIND_RESPECTING_MOVE > 0.9999_dp) then
                        ! If only bind respecting moves allowed
                        ! can't have a loop to a different polymer
                        success=.FALSE.
                        return
                    endif
                    cycle ! don't expand [IT1,IT2] to different polymer
                endif
            endif
            if (otherEnd < 1) cycle
            if (otherEnd < IT1) then  ! Loop to point before IT1
                IB1_temp=IB1-IT1+otherEnd
                IT1_temp=otherEnd
            elseif (otherEnd > IT2) then ! Loop to point after IT2
                IB2_temp=IB2-IT2+otherEnd
                IT2_temp=otherEnd
                exit
            endif
        enddo
        if (IB2_temp-IB1_temp<max_window) then
            ! prevent extremely long crank shaft moves
            IB1=IB1_temp
            IT1=IT1_temp
            IB2=IB2_temp
            IT2=IT2_temp
            if (WLC_P__WARNING_LEVEL >= 1) then
                if (IB2 /= get_IB(IT2) .or. IB1 /= get_IB(IT1)) then
                    print*, "Error in enforce binding"
                    stop 1
                endif
            endif
            return
        else
            if (WLC_P__PROB_BIND_RESPECTING_MOVE > 0.9999_dp)  success=.FALSE.
            return
        endif
        if (WLC_P__WARNING_LEVEL < 1) then
            ! No need to check if we're sure it's taken care of
            return
        endif
    endif ! NO_LEF_CROSSING

    ! Check for any loops out of moved region
    do I =IT1,IT2
        if (WLC_P__NETWORK) then
            do indx = wlc_network_start_index(I),&
                          wlc_network_start_index(I+1)-1
                otherEnd = wlc_other_beads(indx)
                if (otherEnd < IT1 .or. otherEnd > IT2) then
                    success = .False.
                    return
                endif
            enddo
        else
            otherEnd=wlc_ExplicitBindingPair(I)
            if ((otherEnd < IT1 .or. otherEnd > IT2) .and. otherEnd > 0) then
                success = .False.
                return
            endif
        endif
    enddo
endif
end subroutine

subroutine drawWindow(window,maxWindow,enforceBind,rand_stat,IT1,IT2,IB1,IB2,IP,DIB,success)
use params, only: dp
use mersenne_twister
use polydispersity, only: get_IB, length_of_chain, get_IP, get_I
implicit none
real(dp), intent(in) :: WindoW ! Size of window for bead selection
real(dp), intent(in) :: maxWindow
logical, intent(in) :: enforceBind  ! don't do move with internal bind
type(random_stat), intent(inout) :: rand_stat  ! status of random number generator
integer, intent(out) :: IP    ! Test polymer
integer, intent(out) :: IB1   ! Test bead position 1
integer, intent(out) :: IT1   ! Index of test bead 1
integer, intent(out) :: IB2   ! Test bead position 2
integer, intent(out) :: IT2   ! Index of test bead 2
integer, intent(out) :: dib   ! number of beads moved by move (plus or minus a few)
logical, intent(out) :: success
integer irnd(1)
real(dp) urnd(1) ! single random number
integer TEMP
integer length

success = .TRUE.  ! True unless set to false
call random_index(WLC_P__NT,irnd,rand_stat)
IT1 = irnd(1)
IP = get_IP(IT1)
IB1 = get_IB(IT1)
if (WLC_P__WINTYPE.eq.0) then
    IB2 = IB1 +exponential_random_int(window,rand_stat)
elseif (WLC_P__WINTYPE.eq.1.and..not.WLC_P__RING) then
    call random_number(urnd,rand_stat)
    IB2 = IB1 + (2*nint(urnd(1))-1)* &
           exponential_random_int(window,rand_stat)
elseif (WLC_P__WINTYPE.eq.1.and.WLC_P__RING) then
    IB2 = IB1 + exponential_random_int(window,rand_stat)
else
    call stop_if_err(1, "Warning: WLC_P__WINTYPE not recognized")
endif

DIB = IB2-IB1
length = length_of_chain(IP)
if (WLC_P__RING) then
    if (IB2 > length) then
        IB2 = DIB-(length-IB1)
    endif
    if (WLC_P__EXPLICIT_BINDING) then
        print*, "Ring polymer not set up to use explicit binding"
        print*, "Need to write special loop skiping code"
        stop
    endif
    IT2 = get_I(IB2,IP)
    IT1 = get_I(IB1,IP)
else
    if (IB2 > length) then
        IB2 = length
    endif
    if (IB2 < 1) then
       IB2 = 1
    endif
    if (IB2 < IB1) then
        TEMP = IB1
        IB1 = IB2
        IB2 = TEMP
    endif
    IT2 = get_I(IB2,IP)
    IT1 = get_I(IB1,IP)
    if (WLC_P__EXPLICIT_BINDING .and. enforceBind) then
        call enforceBinding(rand_stat,IB1,IB2,IT1,IT2,maxWindow,success)
        if (success .eqv. .False.) return
    endif
endif


DIB = IB2-IB1
end subroutine drawWindow


end module windowTools
