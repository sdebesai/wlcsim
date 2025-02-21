#include "../defines.inc"
!---------------------------------------------------------------*
!
!      Chain backbone potential between two beads
!
! E_wlc(RM1,R,RP1,EB)
! E_SSWLC(R,RM1,U,UM1,EB,EPAR,EPERP,ETA,GAM)
! E_GAUSS(R,RM1,EPAR)
!---------------------------------------------------------------
module MC_wlc
use precision, only: dp
implicit none
contains

function E_wlc(RM1,R,RP1,EB)
    implicit none
    real(dp), intent(in), dimension(3) :: RM1 ! R of bead i-1
    real(dp), intent(in), dimension(3) :: R ! R of bead i
    real(dp), intent(in), dimension(3) :: RP1 ! R of bead i+1
    real(dp), intent(in) :: EB
    real(dp) E_wlc
    real(dp), dimension(3) :: U0, U

    U0 = R - RM1
    U0 = U0/norm2(U0)
    U = RP1 - R
    U = U/norm2(U)
    E_wlc = EB*DOT_PRODUCT(U,U0)
end function E_wlc

function E_SSWLC(R,RM1,U,UM1,EB,EPAR,EPERP,ETA,GAM)
    implicit none
    real(dp), intent(in), dimension(3) :: RM1 ! R of bead i-1
    real(dp), intent(in), dimension(3) :: R ! R of bead i
    real(dp), intent(in), dimension(3) :: UM1 ! U of bead i-1
    real(dp), intent(in), dimension(3) :: U ! U of bead i
    real(dp), intent(in) :: EB, EPAR, EPERP, ETA, GAM ! SSWLC constants
    real(dp), dimension(4) :: E_SSWLC
    real(dp) GI(3)
    real(dp) DR(3)
    real(dp) DRPAR
    real(dp) DRPERP(3)

    DR = R-RM1
    DRPAR = dot_product(DR,UM1)
    DRPERP = DR - DRPAR*UM1
    GI = U - UM1 - ETA*DRPERP
    E_SSWLC(1)=0.5_dp*EB*dot_product(GI,GI)
    E_SSWLC(2)=0.5_dp*EPAR*(DRPAR-GAM)**2
    E_SSWLC(3)=0.5_dp*EPERP*dot_product(DRPERP,DRPERP)
    E_SSWLC(4)=0.0_dp
end function E_SSWLC

function E_SSWLCWT(R,RM1,U,UM1,V,VM1,EB,EPAR,EPERP,ETA,GAM,ETWIST)
    use vector_utils, only: cross, axisAngle, rotateU, angle_between
    implicit none
    real(dp), intent(in), dimension(3) :: RM1 ! R of bead i-1
    real(dp), intent(in), dimension(3) :: R ! R of bead i
    real(dp), intent(in), dimension(3) :: UM1 ! U of bead i-1
    real(dp), intent(in), dimension(3) :: U ! U of bead i
    real(dp), intent(in), dimension(3) :: VM1 ! V of bead i-1
    real(dp), intent(in), dimension(3) :: V ! V of bead i
    real(dp), intent(in) :: EB, EPAR, EPERP, ETA, GAM, ETWIST ! SSWLC constants
    real(dp), dimension(4) :: E_SSWLCWT
    real(dp) GI(3)
    real(dp) DR(3)
    real(dp) DRPAR
    real(dp) DRPERP(3)

    real(dp) TA(3)
    real(dp), parameter :: P(3) = [0.0_dp, 0.0_dp, 0.0_dp]
    real(dp) alpha, mag
    real(dp) ROT(3,4)

    DR = R-RM1
    DRPAR = dot_product(DR,UM1)
    DRPERP = DR - DRPAR*UM1
    GI = U - UM1 - ETA*DRPERP
    E_SSWLCWT(1)=0.5_dp*EB*dot_product(GI,GI)
    E_SSWLCWT(2)=0.5_dp*EPAR*(DRPAR-GAM)**2
    E_SSWLCWT(3)=0.5_dp*EPERP*dot_product(DRPERP,DRPERP)

    ! We find the rotation matrix which takes UM1 to U and apply it to
    ! VM1 and then see how much VM1 differst from V.  The resulting angle
    ! contributes to the twist energy.
    TA = cross(UM1,U)
    mag = norm2(TA)
    if (mag > 10**(-10)) then
        alpha = angle_between(UM1, U)
        TA = TA/mag
        if (isnan(alpha)) then
            print*, "alpha = nan"
            print*, "mag", mag
            print*, "|U|", norm2(U)
            print*, "|UM1|", norm2(UM1)
        endif
        call axisAngle(ROT, alpha, TA, P)
        E_SSWLCWT(4) = 0.5_dp*ETWIST*angle_between(rotateU(ROT,VM1),V)**2
    else
        ! if UM1 ~ U then don't rotate (avoids Nan)
        E_SSWLCWT(4) = 0.5_dp*ETWIST*angle_between(VM1,V)**2
    endif
    ! ETWIST = lt/l0
    if (isnan(E_SSWLCWT(4))) then
        print*, "Nan in twist"
        if (mag > 10**(-10)) then
            print*, "R VM1", rotateU(ROT,VM1)
            print*, "V", V
        else
            print*, "VM1", VM1
            print*, "V", V
            print*, "mag", mag
        endif
    endif



end function E_SSWLCWT

function E_GAUSS(R,RM1,EPAR)
    implicit none
    real(dp), intent(in), dimension(3) :: RM1 ! R of bead i-1
    real(dp), intent(in), dimension(3) :: R ! R of bead i
    real(dp), intent(in) :: EPAR
    real(dp) E_GAUSS
    real(dp) DR(3)
    DR = R-RM1
    E_GAUSS = 0.5_dp*EPAR*dot_product(DR,DR)
    ! in gaussian chain, there's only parallel stretching energy. DEELAS init'd to zeros, so sum(DEELAS) == DEELAS(2) later
end function E_GAUSS

! ------------------------------------------------------------
!    Lookup precultulated WLC parameters
!
!     1. Determine the simulation type
!     2. Evaluate the polymer elastic parameters
!     3. Determine the parameters for Brownian dynamics simulation
! -----------------------------------------------------------
subroutine calc_elastic_constants(DEL,LP,LT,EB,EPAR,GAM,XIR,EPERP,ETA,XIU,DT,SIGMA,&
                                  ETWIST,simtype)
    implicit none
    real(dp), intent(in) :: DEL  ! Number of persistance lengths between beads
    real(dp), intent(in) :: LP   ! Persistance length in units of simulation
    real(dp), intent(in) :: LT   ! Twist persistance length
    real(dp), intent(out) :: EB
    real(dp), intent(out) :: EPAR
    real(dp), intent(out) :: GAM
    real(dp), intent(out) :: XIR
    real(dp), intent(out) :: EPERP
    real(dp), intent(out) :: ETA
    real(dp), intent(out) :: XIU
    real(dp), intent(out) :: DT
    real(dp), intent(out) :: ETWIST
    real(dp), intent(out) :: SIGMA
    integer, intent(out) :: simtype

    integer ind, i
    real(dp) M
    REAL(dp) :: pvec(679, 8) ! array holding dssWLC params calculated by Elena

    !  Please note that when Quinn rewrote this function he changed XIR from
    !  L/(L*LP) to DEL which is L/(LP*(NB-1)).  This is a matter of how you
    !  interperate the meaning of the end beads of the polymer.


        ! std dev of interbead distribution of nearest possible GC, used to initialize sometimes
    !wlc_p%SIGMA = sqrt(2.0_dp*WLC_P__LP*WLC_P__L/3.0_dp)/real(WLC_P__NB - 1)
    SIGMA = LP*sqrt(DEL*2.0_dp/3.0_dp)


!     Load the tabulated parameters

    open (UNIT = 5,FILE = 'input/dssWLCparams',STATUS = 'OLD')
    do I = 1,679
        READ(5,*) PVEC(I,1),PVEC(I,2),PVEC(I,3),PVEC(I,4),PVEC(I,5),PVEC(I,6),PVEC(I,7),PVEC(I,8)
    ENDdo
    CLOSE(5)

!     Setup the parameters for WLC simulation


    ! if del < 0.01
    if (DEL < PVEC(1,1)) then
        PRinT*, 'It has never been known if the WLC code actually works.'
        PRinT*, 'An entire summer student (Luis Nieves) was thrown at this'
        PRinT*, 'problem and it is still not solved.'
        stop 1
        EB = LP/DEL
        GAM = DEL
        !XIR = WLC_P__L/WLC_P__LP/WLC_P__NB
        XIR = DEL
        SIMTYPE = 1

!    Setup the parameters for GC simulation

    ! if del > 10
    elseif (DEL > PVEC(679,1)) then
        EPAR = 1.5/DEL
        GAM = 0.0_dp
        SIMTYPE = 3
        XIR = DEL

!    Setup the parameters for ssWLC simulation
    ! if 0.01 <= del <= 10
    else !  if (DEL >= PVEC(1,1).AND.DEL <= PVEC(679,1)) then
        SIMTYPE = 2

        ! find(del < pvec, 1, 'first')
        inD = 1
        do while (DEL > PVEC(inD,1))
            inD = inD + 1
        enddo

        !     Perform linear interpolations
        I = 2
        M = (PVEC(inD,I)-PVEC(inD-1,I))/(PVEC(inD,1)-PVEC(inD-1,1))
        EB = M*(DEL-PVEC(inD,1)) + PVEC(inD,I)

        I = 3
        M = (PVEC(inD,I)-PVEC(inD-1,I))/(PVEC(inD,1)-PVEC(inD-1,1))
        GAM = M*(DEL-PVEC(inD,1)) + PVEC(inD,I)

        I = 4
        M = (PVEC(inD,I)-PVEC(inD-1,I))/(PVEC(inD,1)-PVEC(inD-1,1))
        EPAR = M*(DEL-PVEC(inD,1)) + PVEC(inD,I)

        I = 5
        M = (PVEC(inD,I)-PVEC(inD-1,I))/(PVEC(inD,1)-PVEC(inD-1,1))
        EPERP = M*(DEL-PVEC(inD,1)) + PVEC(inD,I)

        I = 6
        M = (PVEC(inD,I)-PVEC(inD-1,I))/(PVEC(inD,1)-PVEC(inD-1,1))
        ETA = M*(DEL-PVEC(inD,1)) + PVEC(inD,I)

        I = 7
        M = (PVEC(inD,I)-PVEC(inD-1,I))/(PVEC(inD,1)-PVEC(inD-1,1))
        XIU = M*(DEL-PVEC(inD,1)) + PVEC(inD,I)

        ! The values read in from file are all non-dimentionalized by the
        ! persistance length.  We now re-dimentionalize them.
        ! We also divied by DEL which is also re-dimentionalized.

        EB = LP*EB/(DEL*LP)
        EPAR = EPAR/(DEL*LP*LP)
        EPERP = EPERP/(DEL*LP*LP)
        GAM = DEL*LP*GAM
        ETA = ETA/LP
        XIU = XIU*DEL
        XIR = DEL
        DT = 0.5_dp*XIU/(EPERP*GAM**2)
        ETWIST = LT/(DEL*LP)
    endif

    return
end subroutine calc_elastic_constants
end module
