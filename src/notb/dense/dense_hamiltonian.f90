!! ======================================================================
!! Atomistica - Interatomic potential library
!! https://github.com/pastewka/atomistica
!! Lars Pastewka, lars.pastewka@iwm.fraunhofer.de, and others.
!! See the AUTHORS file in the top-level Atomistica directory.
!!
!! Copyright (2005-2013) Fraunhofer IWM
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

!>
!! General tight-binding methods
!<

#include "macros.inc"
#include "filter.inc"

module dense_hamiltonian
  use libAtoms_module

  use particles
  use materials

  use dense_hamiltonian_type

  implicit none

  private

  public :: dense_hamiltonian_t

  !
  ! Interfaces
  !

  public :: init
  interface init
     module procedure dense_hamiltonian_init
  endinterface

  public :: del
  interface del
     module procedure dense_hamiltonian_del
  endinterface

  public :: assign_orbitals
  interface assign_orbitals
     module procedure dense_hamiltonian_assign_orbitals
  endinterface

  public :: e_atomic
  interface e_atomic
     module procedure dense_hamiltonian_e_atomic
  endinterface

contains

  !**********************************************************************
  ! Constructor
  !**********************************************************************
  subroutine dense_hamiltonian_init(this, mat, p, f, error)
    implicit none

    type(dense_hamiltonian_t),           intent(inout) :: this
    type(materials_t), target,           intent(in)    :: mat
    type(particles_t), target, optional, intent(in)    :: p
    integer,                   optional, intent(in)    :: f
    integer,                   optional, intent(inout) :: error

    ! ---

    INIT_ERROR(error)

    this%mat = c_loc(mat)

#ifdef _MP
    if (mod(this%nk, mpi_n_procs()) /= 0) then
       RAISE_ERROR("The number of k-points (" // this%nk // ") must be a multiple of the number of processes (" // mpi_n_procs() // ".", error)
    endif

    this%startk = int(this%nk/mpi_n_procs())*mpi_id()+1
    this%endk = int(this%nk/mpi_n_procs())*(mpi_id()+1)
#endif

    this%f = 0
    if (present(f)) then
       this%f = f
    endif

    if (present(p)) then
       call assign_orbitals(this, p, error)
    endif

  endsubroutine dense_hamiltonian_init


  !**********************************************************************
  ! Destructor
  !**********************************************************************
  subroutine dense_hamiltonian_del(this)
    implicit none

    type(dense_hamiltonian_t), target :: this

    ! ---

    call dense_hamiltonian_deallocate(c_loc(this))

  endsubroutine dense_hamiltonian_del


  !**********************************************************************
  ! Set the particles object
  !**********************************************************************
  subroutine dense_hamiltonian_assign_orbitals(this, p, error)
    implicit none

    type(dense_hamiltonian_t), target     :: this
    type(particles_t), target, intent(in) :: p
    integer, intent(inout), optional      :: error

    ! ---

    integer   :: i, j, enr, enrj, ia
    real(DP)  :: c
#ifdef LAMMPS
    logical   :: found
#endif

    type(materials_t),    pointer :: this_mat
    type(notb_element_t), pointer :: this_at(:)

    ! ---

    INIT_ERROR(error)

    call timer_start("dense_hamiltonian_assign_orbitals")

    this%p = c_loc(p)
    call c_f_pointer(this%mat, this_mat)

    this%el = c_loc(p%el(1))

    !
    ! Determine the total number of orbitals
    !

    c = 0.0
    this%norb = 0
    do i = 1, p%natloc

       if (IS_EL(this%f, p, i)) then

          if (.not. element_by_Z(this_mat, p%el2Z(p%el(i)), enr=enr)) then
              RAISE_ERROR("[notb_init] Unknown element '" // p%el2Z(p%el(i)) // "' encountered.", error)
          endif

          this%norb = this%norb + this_mat%e(enr)%no

          do j = 1, i
             
             if (IS_EL(this%f, p, j)) then

                if (.not. element_by_Z(this_mat, p%el2Z(p%el(j)), enr=enrj)) then
                   RAISE_ERROR("[notb_init] Unknown element '" // p%el2Z(p%el(j)) // "' encountered.", error)
                endif

                c = max(c, this_mat%cut(enr, enrj))
                c = max(c, this_mat%R(enr, enrj)%cut)
                
             endif

          enddo

       endif

    enddo

    this%cutoff = c

    call dense_hamiltonian_allocate(c_loc(this), p%nat, this%norb)
    call c_f_pointer(this%at, this_at, [this%nat])

    ia   = 1
    do i = 1, p%nat

       if (IS_EL(this%f, p, i)) then

#ifdef LAMMPS
          if (i <= p%natloc) then
#endif

             if (.not. element_by_Z(this_mat, p%el2Z(p%el(i)), enr=enr)) then
                RAISE_ERROR("[notb_init] Unknown element '" // p%el2Z(p%el(i)) // "' encountered.", error)
             endif
             this_at(i)     = this_mat%e(enr)
             this_at(i)%o1  = ia
             ia             = ia + this_at(i)%no

!             write (*, *) i // " is " // this_at(i)%enr

#ifdef LAMMPS
          else
             ! FIXME!!! Slow, but should not be the time relevant step in TB
             found = .false.
             do j = 1, p%natloc
                if (p%tag(i) == p%tag(j)) then
                   this_at(i) = this_at(j)
!                   write (*, *) i // "->" // j // "; " // p%tag(i) // "->" // p%tag(j) // "; is " // this_at(i)%enr
                   found = .true.
                endif
             enddo

             if (.not. found) then
                RAISE_ERROR("Could not find tag " // p%tag(i) // " of atom " // i // " in simulation.", error)
             endif
          endif
#endif

       endif

    enddo

    call timer_stop("dense_hamiltonian_assign_orbitals")

  endsubroutine dense_hamiltonian_assign_orbitals


  !>
  !! Atomic energies
  !!
  !! Return the energy of the system decomposed into charge neutral
  !! isolated atoms.
  !!
  !<
  real(DP) function dense_hamiltonian_e_atomic(this, p, error) result(e)
    implicit none

    type(dense_hamiltonian_t), intent(in)     :: this   !< Hamiltonian object
    type(particles_t),         intent(in)     :: p
    integer,         optional, intent(inout)  :: error  !< Error signals

    ! ---

    integer  :: i, q0

    type(notb_element_t), pointer  :: at(:)

    ! ---

    INIT_ERROR(error)
    
    call c_f_pointer(this%at, at, [this%nat])

    e = 0.0_DP
    do i = 1, p%natloc
       q0 = int(at(i)%q0)

       e = e + 2*sum(at(i)%e(1:q0/2))
       if (mod(q0, 2) /= 0) then
          e = e + at(i)%e(q0/2+1)
       endif
    enddo

  endfunction dense_hamiltonian_e_atomic

endmodule dense_hamiltonian