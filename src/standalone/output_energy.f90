!! ======================================================================
!! Atomistica - Interatomic potential library and molecular dynamics code
!! https://github.com/Atomistica/atomistica
!!
!! Copyright (2005-2015) Lars Pastewka <lars.pastewka@kit.edu> and others
!! See the AUTHORS file in the top-level Atomistica directory.
!!
!! This program is free software: you can redistribute it and/or modify
!! it under the terms of the GNU General Public License as published by
!! the Free Software Foundation, either version 2 of the License, or
!! (at your option) any later version.
!!
!! This program is distributed in the hope that it will be useful,
!! but WITHOUT ANY WARRANTY; without even the implied warranty of
!! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!! GNU General Public License for more details.
!!
!! You should have received a copy of the GNU General Public License
!! along with this program.  If not, see <http://www.gnu.org/licenses/>.
!! ======================================================================
! @meta
!   shared
!   classtype:output_energy_t classname:OutputEnergy interface:callables
! @endmeta

!>
!! Continuously output energy information to a file
!!
!! Continuously output energy information to a file
!<

#include "macros.inc"

module output_energy
  use supplib

  use particles
  use dynamics
  use neighbors
  use filter

  use potentials
  use coulomb

#ifdef _MP
  use communicator
#endif

  implicit none

  private

  public :: output_energy_t
  type output_energy_t

     real(DP)  :: freq

     integer   :: un

     !
     ! Averaging
     !

     real(DP)  :: t
     real(DP)  :: ekin
     real(DP)  :: epot
     real(DP)  :: ecoul
     real(DP)  :: ebs
     real(DP)  :: erep
     real(DP)  :: mu
     real(DP)  :: P(3, 3)
     real(DP)  :: V

     !
     ! Additional variable attributes from the data structure
     !

     integer                :: n_real_attr
     integer, allocatable   :: l2d(:)
     real(DP), allocatable  :: real_attr(:)

     !
     ! Output format str
     !

     character(256)  :: fmt_str

  endtype output_energy_t


  public :: init
  interface init
     module procedure output_energy_init
  endinterface

  public :: del
  interface del
     module procedure output_energy_del
  endinterface

  public :: bind_to_with_pots
  interface bind_to_with_pots
     module procedure output_energy_bind_to
  endinterface

! NOT REQUIRED
!  interface register_data
!     module procedure output_energy_register_data
!  endinterface

  public :: invoke_with_pots
  interface invoke_with_pots
     module procedure output_energy_invoke
  endinterface

  public :: register
  interface register
    module procedure output_energy_register
  endinterface

contains
  

  !>
  !! Constructor
  !!
  !! Initialize a output_energy object
  !<
  subroutine output_energy_init(this)
    implicit none

    type(output_energy_t), intent(inout)  :: this

    ! ---

#ifdef _MP
    if (mpi_id() == 0) then
#endif

    call prlog("- output_energy_init -")
    call prlog("     freq = " // this%freq)
    call prlog

#ifdef _MP
    endif
#endif

  endsubroutine output_energy_init

  !>
  !! Destructor
  !!
  !! Delete a output_energy object
  !<
  subroutine output_energy_del(this)
    implicit none

    type(output_energy_t), intent(inout)  :: this

    ! ---

#ifdef _MP
    if (mpi_id() == 0) then
#endif
       call fclose(this%un)
#ifdef _MP
    endif
#endif

    if (allocated(this%l2d)) then
       deallocate(this%l2d)
    endif
    if (allocated(this%real_attr)) then
       deallocate(this%real_attr)
    endif

  endsubroutine output_energy_del


  !>
  !! Notify the energy output object of the Particles and Neighbors objects
  !<
  subroutine output_energy_bind_to(this, p, nl, pots_cptr, ierror)
    use, intrinsic :: iso_c_binding

    implicit none

    type(output_energy_t), intent(inout) :: this
    type(particles_t),     intent(inout) :: p
    type(neighbors_t),     intent(inout) :: nl
    type(C_PTR),           intent(in)    :: pots_cptr
    integer,     optional, intent(out)   :: ierror

    ! ---

    integer          :: i
    character(1024)  :: hdr

    ! ---

#ifdef _MP
    if (mpi_id() == 0) then
#endif
  
    call prlog("- output_energy_bind_to -")

    this%n_real_attr = 0
    do i = 1, p%data%n_real_attr
       if (iand(p%data%tag_real_attr(i), F_TO_ENER) /= 0) then
          this%n_real_attr = this%n_real_attr + 1
       endif
    enddo

    if (this%n_real_attr > 0) then
       call prlog("     " // this%n_real_attr // " additional attributes " // &
            "found for output")
       allocate(this%l2d(this%n_real_attr))
       allocate(this%real_attr(this%n_real_attr))

       this%n_real_attr = 0
       do i = 1, p%data%n_real_attr
          if (iand(p%data%tag_real_attr(i), F_TO_ENER) /= 0) then
             this%n_real_attr = this%n_real_attr + 1
             this%l2d(this%n_real_attr) = i
          endif
       enddo
    endif

    this%un = fopen("ener.out", F_WRITE)

    this%fmt_str = "(I9,X,"//(18+this%n_real_attr)//"ES20.10)"
    hdr = "#1:it 2:time 3:ekin 4:epot 5:ecoul 6:epot+ecoul 7:ekin+epot+ecoul"//&
         " 8:ebs 9:erep 10:mu 11:T 12:P 13:Pxx 14:Pyy 15:Pzz 16:Pxy 17:Pyz "//&
         "18:Pzx 19:V"
    do i = 1, this%n_real_attr
       hdr = trim(hdr) // " " // (19+i) // ":" // &
            p%data%name_real_attr(this%l2d(i))
    enddo
    write (this%un, '(A)')  trim(hdr)

    this%t        = 0.0_DP
    this%ekin     = 0.0_DP
    this%epot     = 0.0_DP
    this%ecoul    = 0.0_DP
    this%ebs      = 0.0_DP
    this%erep     = 0.0_DP
    this%mu       = 0.0_DP
    this%P(:, :)  = 0.0_DP
    this%V        = 0.0_DP

    if (this%n_real_attr > 0) then
       this%real_attr = 0.0_DP
    endif

    call prlog

#ifdef _MP
    endif
#endif

  endsubroutine output_energy_bind_to


  !>
  !! Write energies to the output file
  !!
  !! Write energies to the output file
  !<
  subroutine output_energy_invoke(this, dyn, nl, pots_cptr, coul, ierror)
    use, intrinsic :: iso_c_binding

    implicit none

    type(output_energy_t), intent(inout) :: this
    type(dynamics_t),      target        :: dyn
    type(neighbors_t),     target        :: nl
    type(C_PTR),           intent(in)    :: pots_cptr
    type(C_PTR),           intent(in)    :: coul
    integer,     optional, intent(out)   :: ierror

    ! ---

    integer   :: i
    real(DP)  :: pr, T

    ! ---

    INIT_ERROR(ierror)

    this%t = this%t + dyn%dt

    this%ekin     = this%ekin     + dyn%ekin * dyn%dt
    this%epot     = this%epot     + dyn%epot * dyn%dt
    this%p(:, :)  = this%p(:, :)  + dyn%pressure(:, :) * dyn%dt
    this%V        = this%V        + volume(dyn%p) * dyn%dt

    this%ecoul = this%ecoul   + coulomb_get_potential_energy(coul) * dyn%dt

!    if (associated(mod_tb)) then
!       this%ebs   = this%ebs    + mod_tb%tb%ebs * dyn%dt
!       this%erep  = this%erep   + mod_tb%tb%erep * dyn%dt
!       this%mu    = this%mu     + mod_tb%tb%mu * dyn%dt
!    endif

    if (this%n_real_attr > 0) then
       do i = 1, this%n_real_attr
          this%real_attr(i) = this%real_attr(i) + &
               dyn%p%data%data_real_attr(this%l2d(i))*dyn%dt
       enddo
    endif

    if (this%freq < 0 .or. this%t >= this%freq) then

       this%ekin     = this%ekin / this%t
       this%epot     = this%epot / this%t
       this%p(:, :)  = this%p(:, :) / this%t
       this%V        = this%V / this%t

       if (coulomb_is_enabled(coul)) then
          this%ecoul = this%ecoul / this%t
       endif

!       if (associated(mod_tb)) then
!          this%ebs   = this%ebs / this%t
!          this%erep  = this%erep / this%t
!          this%mu    = this%mu / this%t
!       endif

       T  = this%ekin*2/(dyn%p%dof*K_to_energy)  ! eV/A                                                                                                                                   
       pr = tr(3, this%p) / 3

       if (this%n_real_attr > 0) then
          this%real_attr = this%real_attr / this%t
       endif

#ifdef _MP
       if (mpi_id() == 0) then
#endif

       if (this%n_real_attr > 0) then
          write (this%un, this%fmt_str)  dyn%it, dyn%ti, &
               this%ekin, this%epot-this%ecoul, this%ecoul, this%epot, &
               this%ekin+this%epot, this%ebs, this%erep, this%mu, T, &
               pr, this%p(1, 1), this%p(2, 2), this%p(3, 3), &
               (this%p(1, 2)+this%p(2, 1))/2, &
               (this%p(2, 3)+this%p(3, 2))/2, &
               (this%p(3, 1)+this%p(1, 3))/2, &
               this%V, &
               this%real_attr
       else
          write (this%un, this%fmt_str)  dyn%it, dyn%ti, &
               this%ekin, this%epot-this%ecoul, this%ecoul, this%epot, &
               this%ekin+this%epot, this%ebs, this%erep, this%mu, T, &
               pr, this%p(1, 1), this%p(2, 2), this%p(3, 3), &
               (this%p(1, 2)+this%p(2, 1))/2, &
               (this%p(2, 3)+this%p(3, 2))/2, &
               (this%p(3, 1)+this%p(1, 3))/2, &
               this%V
       endif

#ifdef _MP
    endif
#endif

      this%t        = 0.0_DP
      this%ekin     = 0.0_DP
      this%epot     = 0.0_DP
      this%ecoul    = 0.0_DP
      this%ebs      = 0.0_DP
      this%erep     = 0.0_DP
      this%mu       = 0.0_DP
      this%P(:, :)  = 0.0_DP
      this%V        = 0.0_DP

      if (this%n_real_attr > 0) then
         this%real_attr = 0.0_DP
      endif

    endif

  endsubroutine output_energy_invoke


  subroutine output_energy_register(this, cfg, m)
    use, intrinsic :: iso_c_binding

    implicit none

    type(output_energy_t), target, intent(inout)  :: this
    type(c_ptr), intent(in)               :: cfg
    type(c_ptr), intent(out)              :: m

    ! ---

    m = ptrdict_register_section(cfg, CSTR("OutputEnergy"), &
         CSTR("Output the energy of the system to the file 'ener.out'."))

    call ptrdict_register_real_property(m, c_loc(this%freq), CSTR("freq"), &
         CSTR("Output frequency (-1 means output every time step)."))

  endsubroutine output_energy_register

endmodule output_energy