module sea_level

    use isostasy_defs, only : wp, isos_class
    use isos_utils

    implicit none

    public :: calc_columnanoms_load
    public :: calc_columnanoms_solidearth
    ! public :: calc_seasurfaceheight
    public :: calc_masks
    public :: calc_sl_contribution

    contains

    ! calc_sealevel()
    ! Update the sea level based on the new ice thickness field
    ! subroutine calc_sealevel(Hice, isos, update_diagnostics)
    !     implicit none
    !     real(wp), intent(IN)            :: Hice(:,:)
    !     type(isos_class), intent(INOUT) :: isos
    !     logical, intent(IN)             :: update_diagnostics

    !     call calc_columnanoms_load(Hice, isos)  ! Part 1
    !     call calc_columnanoms_solidearth(isos)

    !     if (update_diagnostics) then
    !         call calc_seasurfaceheight(isos)    ! Part 2
    !         call calc_masks(isos)               ! Part 3
    !         call calc_sl_contribution(isos)     ! Part 4
    !         isos%now%count_updates = isos%now%count_updates + 1
    !     endif

    !     return
    ! end subroutine calc_sealevel

    
    !!!!!!!!!!!!!!!!!!!!!! Part 1 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    subroutine calc_columnanoms_load(Hice, isos)
        implicit none
        real(wp), intent(IN)                :: Hice(:,:)
        type(isos_class), intent(INOUT)     :: isos 

        isos%now%Hice = Hice
        call maskfield(isos%now%Hsw, isos%now%ssh - isos%now%z_bed, isos%now%maskocean, &
            isos%domain%nx, isos%domain%ny)

        isos%now%canom_load(:, :) = 0
        call add_columnanom(isos%par%rho_ice, isos%now%Hice, isos%ref%Hice, isos%now%canom_load)
        call add_columnanom(isos%par%rho_seawater, isos%now%Hsw, isos%ref%Hsw, isos%now%canom_load)
    end subroutine calc_columnanoms_load

    !
    subroutine calc_columnanoms_solidearth(isos)
        implicit none
        type(isos_class), intent(INOUT)   :: isos

        isos%now%canom_full = isos%now%canom_load
        call add_columnanom(isos%par%rho_litho, isos%now%we, isos%ref%we, isos%now%canom_full)
        call add_columnanom(isos%par%rho_uppermantle, isos%now%w, isos%ref%w, isos%now%canom_full)
        return
    end subroutine calc_columnanoms_solidearth

    !
    subroutine add_columnanom(rho, H_now, H_ref, canom)
        implicit none

        real(wp), intent(IN)    :: rho
        real(wp), intent(IN)    :: H_now(:,:)
        real(wp), intent(IN)    :: H_ref(:,:)
        real(wp), intent(INOUT) :: canom(:,:)

        canom = canom + rho * (H_now - H_ref)
        return
    end subroutine add_columnanom

    !!!!!!!!!!!!!!!!!!!!!! Part 2 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    subroutine calc_seasurfaceheight(isos)
        implicit none
        type(isos_class), intent(INOUT)   :: isos

        call calc_ssh_perturbation(isos)
        isos%now%ssh = isos%ref%ssh + isos%now%ssh_perturb + isos%now%bsl
    end subroutine calc_seasurfaceheight


    subroutine calc_ssh_perturbation(isos)
        implicit none
        type(isos_class), intent(INOUT)   :: isos

        call calc_mass_anom(isos)
        !call calc_fft_convo()
    end subroutine calc_ssh_perturbation

    !
    subroutine calc_mass_anom(isos)
        implicit none
        type(isos_class), intent(INOUT)   :: isos 

        call maskfield(isos%now%mass_anom, isos%domain%A * isos%now%canom_full, &
            isos%domain%maskactive, isos%domain%nx, isos%domain%ny)
        return
    end subroutine calc_mass_anom

    !!!!!!!!!!!!!!!!!!!!!! Part 3 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    subroutine calc_masks(isos)
        implicit none
        type(isos_class), intent(INOUT)   :: isos

        isos%now%maskcontinent = (isos%now%ssh - isos%now%z_bed) > 0

        ! maskgrounded
        call calc_height_above_floatation(isos)
        isos%now%maskgrounded = isos%now%Haf > 0

        call calc_maskocean(isos)

        return
    end subroutine calc_masks

    subroutine calc_maskocean(isos)
        implicit none
        
        type(isos_class), intent(INOUT) :: isos
        integer                         :: i, j

        do i = 1, isos%domain%nx
            do j = 1, isos%domain%ny
                if (isos%now%maskcontinent(i, j) .or. isos%now%maskgrounded(i, j)) then
                    isos%now%maskocean(i, j) = .true.
                else
                    isos%now%maskocean(i, j) = .false.
                endif
            enddo
        enddo

    end subroutine calc_maskocean

    !
    subroutine calc_height_above_floatation(isos)
        implicit none
        type(isos_class), intent(INOUT) :: isos
        real(wp), allocatable           :: Heq(:, :)
        real(wp), allocatable           :: Heq_masked(:, :)

        allocate(Heq(isos%domain%nx, isos%domain%ny))
        Heq = isos%now%z_bed - isos%now%ssh

        ! TODO: check if min function appropriate for arrays
        call maskfield(Heq_masked, Heq, Heq > 0, isos%domain%nx, isos%domain%ny)

        isos%now%Haf = isos%now%Hice + Heq_masked * (isos%par%rho_seawater / isos%par%rho_ice)
    end subroutine calc_height_above_floatation

    !!!!!!!!!!!!!!!!!!!!!! Part 4 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    subroutine calc_sl_contribution(isos)
        implicit none
        type(isos_class), intent(INOUT)   :: isos 
        real(wp) :: V_af
        real(wp) :: V_den
        ! real(wp) :: V_pov

        V_af = sum( (isos%now%Haf - isos%ref%Haf ) * isos%domain%A )
        V_den = sum((isos%now%Hice - isos%ref%Hice) * isos%par%Vden_factor * isos%domain%A)
        isos%now%bsl = (V_af + V_den) / isos%par%A_ocean_pd
        return
    end subroutine calc_sl_contribution

end module sea_level