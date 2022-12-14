program test_isostasy

    use ncio
    !use yelmo 
    use isostasy 

    implicit none

    ! Internal constants
    integer,  parameter :: dp  = kind(1.d0)
    integer,  parameter :: sp  = kind(1.0)

    ! Choose the precision of the library (sp,dp)
    integer,  parameter :: wp = sp 


    character(len=512) :: outfldr
    character(len=512) :: path_par
    character(len=512) :: file_out 

    character(len=56)  :: experiment 

    real(wp) :: time 
    real(wp) :: time_init 
    real(wp) :: time_end 
    real(wp) :: dtt 
    integer  :: n, nt 

    integer  :: i, j, nx, ny 
    real(wp) :: xmin, xmax, dx 
    real(wp), allocatable :: xc(:)
    real(wp), allocatable :: yc(:)

    real(wp), allocatable :: z_bed_ref(:,:) 
    real(wp), allocatable :: H_ice_ref(:,:) 
    real(wp), allocatable :: z_sl_ref(:,:) 
    
    real(wp), allocatable :: z_bed(:,:) 
    real(wp), allocatable :: H_ice(:,:) 
    real(wp), allocatable :: z_sl(:,:) 
    
    real(wp), allocatable :: mask(:,:) 

    type(isos_class) :: isos1

    ! === Define runtime information =========
    ! program runs from yelmox/
    ! executable is defined in libyelmox/bin/test_isostasy.x 
    ! output directory should be predefined: output/test-isostasy

    outfldr = "output/test-isostasy"
    path_par = trim(outfldr)//"/"//"test_isostasy.nml" 
    file_out = trim(outfldr)//"/"//"bedtest.nc"

    write(*,*) "outfldr: ",  trim(outfldr)
    write(*,*) "path_par: ", trim(path_par)
    write(*,*) "file_out: ", trim(file_out)
    
    ! === Define experiment to be run ====

    experiment = "constant_thickness"
    !experiment = "variable_tau"
    !experiment = "point_load"
    
    write(*,*) "experiment = ", trim(experiment)

    ! === Define simulation time ========

    time_init = 0.0
    time_end  = 2e3  
    dtt       = 200.0 

    write(*,*) "time_init = ", time_init 
    write(*,*) "time_end  = ", time_end 
    write(*,*) "dtt       = ", dtt 

    ! === Define grid information ============

    dx = 20.0e3

    xmin = -2000.0e3
    xmax = abs(xmin)
    nx   = int( (xmax-xmin) / dx ) + 1 

    allocate(xc(nx))
    allocate(yc(nx))

    do i = 1, nx 
        xc(i) = xmin + (i-1)*dx 
    end do

    ny = nx 
    yc = xc 

    write(*,*) "Grid info: " 
    write(*,*) "dx = ", dx 
    write(*,*) "nx, ny = ", nx, ny 
    write(*,*) "range(xc): ", minval(xc), maxval(xc) 
    write(*,*) "range(yc): ", minval(yc), maxval(yc) 
    
    ! === Define topography fields =========

    allocate(z_bed_ref(nx,ny))
    allocate(H_ice_ref(nx,ny))
    allocate(z_sl_ref(nx,ny))
    allocate(z_bed(nx,ny))
    allocate(H_ice(nx,ny))
    allocate(z_sl(nx,ny))
    
    allocate(mask(nx,ny)) 

    z_bed_ref   = 0.0 
    H_ice_ref   = 0.0 
    z_sl_ref    = 0.0 
    
    z_bed       = 0.0 
    H_ice       = 0.0  
    z_sl        = 0.0 
    
    write(*,*) "Initial fields defined."


    ! Initialize bedrock model (allocate fields)
    call isos_init(isos1,path_par,nx,ny,dx)


    ! Define ice thickness field based on experiment being run...
    
    select case(trim(experiment))

        case("constant_thickness")
            ! Set ice thickness to a constant value everywhere

            H_ice = 1000.0

        case("variable_tau")
            ! Set ice thickness to a constant value everywhere,
            ! with a spatially variable field of tau

            H_ice = 1000.0

            ! Define a mask with three different regions, which will
            ! correspond to different values of tau
            mask(1:int(nx/3.0),:) = 0.0 
            mask(int(nx/3.0)+1:2*int(nx/3.0),:) = 1.0 
            mask(2*int(nx/3.0)+1:nx,:) = 2.0 

            ! Define tau field using the mask
            call isos_set_field(isos1%now%tau,[1e2,1e3,3e3],[0.0_wp,1.0_wp,2.0_wp],mask,dx,sigma=150e3)
        
        case("point_load")
            ! Define ice thickness only in one grid point 

            H_ice = 0.0 
            H_ice(int((nx-1)/2),int((ny-1)/2)) = 1000.0 

        case DEFAULT

            write(*,*) "Error: experiment name not recognized."
            write(*,*) "experiment = ", trim(experiment)
            stop 

    end select


    ! Inititalize state
    call isos_init_state(isos1,z_bed,H_ice,z_sl,z_bed_ref,H_ice_ref,z_sl_ref,time=time_init)


    ! Initialize writing output
    call isos_write_init(isos1,xc,yc,file_out,time_init)


    ! Determine total number of iterations to run
    nt = ceiling((time_end-time_init)/dtt) + 1 

    ! Advance isostasy model
    do n = 1, nt 

        ! Advance time 
        time = time_init + (n-1)*dtt 

        ! Update bedrock
        call isos_update(isos1,H_ice,z_sl,time)

        ! Write to file 
        call isos_write_step(isos1,file_out,time,H_ice,z_sl)

        write(*,*) "time = ", time 

    end do 

contains


    subroutine isos_write_init(isos,xc,yc,filename,time_init)

        implicit none 

        type(isos_class), intent(IN) :: isos 
        real(wp),         intent(IN) :: xc(:)
        real(wp),         intent(IN) :: yc(:)
        character(len=*), intent(IN) :: filename 
        real(wp),         intent(IN) :: time_init
        
        ! Local variables
        integer :: nf
        
        ! Create the empty netcdf file
        call nc_create(filename)

        ! Add grid axis variables to netcdf file
        call nc_write_dim(filename,"xc",x=xc*1e-3,units="km")
        call nc_write_dim(filename,"yc",x=yc*1e-3,units="km")
        call nc_write_dim(filename,"time",x=time_init,dx=1.0_wp,nx=1,units="kiloyear",unlimited=.TRUE.)

        ! Write dimensions for regional filter too
        call nc_write_dim(filename,"xf",x=0,dx=1,nx=size(isos%now%G0,1),units="pt")
        call nc_write_dim(filename,"yf",x=0,dx=1,nx=size(isos%now%G0,2),units="pt")

        ! Write constant fields 
        call nc_write(filename,"z_bed_ref",isos%now%z_bed_ref,units="m",long_name="Bedrock elevation reference", &
                        dim1="xc",dim2="yc",start=[1,1]) 

        call nc_write(filename,"tau",isos%now%tau,units="yr",long_name="Asthenosphere relaxation timescale", &
                        dim1="xc",dim2="yc",start=[1,1]) 

        call nc_write(filename,"kei",isos%now%kei,units="",long_name="Kelvin function filter", &
                        dim1="xf",dim2="yf",start=[1,1]) 
        call nc_write(filename,"G0",isos%now%G0,units="",long_name="Regional elastic plate filter", &
                        dim1="xf",dim2="yf",start=[1,1]) 

        return

    end subroutine isos_write_init

    subroutine isos_write_step(isos,filename,time,H_ice,z_sl)

        implicit none 
        
        type(isos_class), intent(IN) :: isos        
        character(len=*), intent(IN) :: filename
        real(wp),         intent(IN) :: time
        real(wp),         intent(IN) :: H_ice(:,:) 
        real(wp),         intent(IN) :: z_sl(:,:) 

        ! Local variables
        integer  :: ncid, n
        real(wp) :: time_prev 

        ! Open the file for writing
        call nc_open(filename,ncid,writable=.TRUE.)

        ! Determine current writing time step 
        n = nc_size(filename,"time",ncid)
        call nc_read(filename,"time",time_prev,start=[n],count=[1],ncid=ncid) 
        if (abs(time-time_prev).gt.1e-5) n = n+1 

        ! Update the time step
        call nc_write(filename,"time",time,dim1="time",start=[n],count=[1],ncid=ncid)

        ! Write variables

        call nc_write(filename,"H_ice",H_ice,units="m",long_name="Ice thickness", &
              dim1="xc",dim2="yc",dim3="time",start=[1,1,n],ncid=ncid)
        call nc_write(filename,"z_sl",z_sl,units="m",long_name="Sea level elevation", &
              dim1="xc",dim2="yc",dim3="time",start=[1,1,n],ncid=ncid)
        call nc_write(filename,"z_bed",isos%now%z_bed,units="m",long_name="Bedrock elevation", &
                        dim1="xc",dim2="yc",dim3="time",start=[1,1,n],ncid=ncid) 
        call nc_write(filename,"dzbdt",isos%now%dzbdt,units="m/yr",long_name="Bedrock elevation change", &
                        dim1="xc",dim2="yc",dim3="time",start=[1,1,n],ncid=ncid) 

        ! Close the netcdf file
        call nc_close(ncid)

        return 

    end subroutine isos_write_step

end program test_isostasy

