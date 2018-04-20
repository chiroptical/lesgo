!!
!!  Copyright (C) 2009-2018  Johns Hopkins University
!!
!!  This file is part of lesgo.
!!
!!  lesgo is free software: you can redistribute it and/or modify
!!  it under the terms of the GNU General Public License as published by
!!  the Free Software Foundation, either version 3 of the License, or
!!  (at your option) any later version.
!!
!!  lesgo is distributed in the hope that it will be useful,
!!  but WITHOUT ANY WARRANTY; without even the implied warranty of
!!  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!!  GNU General Public License for more details.
!!
!!  You should have received a copy of the GNU General Public License
!!  along with lesgo.  If not, see <http://www.gnu.org/licenses/>.

!*******************************************************************************
module data_writer
!*******************************************************************************
use types, only : rprec
use param, only : write_endian, nz, nz_tot
use messages
#ifdef PPMPI
use mpi
use param, only : nproc, coord, comm, ierr, MPI_RPREC
#endif
#ifdef PPCGNS
use cgns
#endif
implicit none

private
public :: data_writer_t

!  Sums performed over time
type data_writer_t
    integer :: fid
    logical :: opened = .false.
    integer :: nx, ny
    integer :: counter
#ifdef PPMPI
integer :: nz_end
#ifdef PPCGNS
    integer :: base = 1
    integer :: zone = 1
    integer :: sol = 1
    integer(cgsize_t) :: start_n(3)
    integer(cgsize_t) :: end_n(3)
#else
    integer :: subarray_t
#endif
#endif
    integer :: num_fields
contains
    procedure, public :: open_file
    procedure, public :: write_field
    procedure, public :: close_file
end type data_writer_t

contains

!*******************************************************************************
subroutine open_file(this, fname, nx, ny, x, y, z, num_fields)
!*******************************************************************************
use mpi
use string_util
class(data_writer_t), intent(inout) :: this
character(*), intent(in) :: fname
! Size of the plane to write
integer, intent(in) :: nx, ny
! Coordinate system
real(rprec), intent(in), dimension(:) :: x, y, z
! Number of fields
integer :: num_fields
! Full file name with extension
character(64) :: full_fname
! Extension
character(64) :: ext

#ifdef PPCGNS
! Sizes
integer(cgsize_t) :: sizes(3,3)
! Local mesh
real(rprec), dimension(:,:,:), allocatable :: xyz
! Loop through arrays
integer :: i
#endif

! Set the number of fields to write
this%num_fields = num_fields

! Concatenate extension onto filename
full_fname = fname
#ifdef PPCGNS
ext = '.cgns'
#else
ext = '.bin'
#endif
call string_concat(full_fname, ext)

! Open file if not already open
if (this%opened) call error('data_writer_t%open_file', 'File already opened')
#ifdef PPMPI
#ifdef PPCGNS
! Open CGNS file
call cgp_open_f(full_fname, CG_MODE_WRITE, this%fid, ierr)
if (ierr .ne. CG_OK) call cgp_error_exit_f
#else
! Open MPI file
call mpi_file_open(comm, full_fname, MPI_MODE_WRONLY + MPI_MODE_CREATE,        &
    MPI_INFO_NULL, this%fid, ierr)
#endif
#else
! Open simple fortran file
open(newunit=this%fid, file=full_fname, form='unformatted',                    &
    convert=write_endian, access='direct', recl=nx*ny*nz*rprec)
#endif

! Set size of record
this%nx = nx
this%ny = ny

! Set record counter
this%counter = 1

#ifdef PPMPI
! Specify overlap ending
if ( coord == nproc-1 ) then
    this%nz_end = nz
else
    this%nz_end = nz-1
end if

#ifdef PPCGNS
! Write this%base
call cg_base_write_f(this%fid, 'this%base', 3, 3, this%base, ierr)
if (ierr .ne. CG_OK) call cgp_error_exit_f

! Sizes, used to create this%zone
sizes(:,1) = (/int(nx, cgsize_t),int(ny, cgsize_t),int(nz_tot, cgsize_t)/)
sizes(:,2) = (/int(nx-1, cgsize_t),int(ny-1, cgsize_t),int(nz_tot-1, cgsize_t)/)
sizes(:,3) = (/int(0, cgsize_t) , int(0, cgsize_t), int(0, cgsize_t)/)

! Write this%zone
call cg_zone_write_f(this%fid, this%base, 'this%zone', sizes, Structured,      &
    this%zone, ierr)
if (ierr .ne. CG_OK) call cgp_error_exit_f

! Create data nodes for coordinates
call cgp_coord_write_f(this%fid, this%base, this%zone, RealDouble,             &
    'CoordinateX', nx*ny*this%nz_end, ierr)
if (ierr .ne. CG_OK) call cgp_error_exit_f
call cgp_coord_write_f(this%fid, this%base, this%zone, RealDouble,             &
    'CoordinateY', nx*ny*this%nz_end, ierr)
if (ierr .ne. CG_OK) call cgp_error_exit_f
call cgp_coord_write_f(this%fid, this%base, this%zone, RealDouble,             &
    'CoordinateZ', nx*ny*this%nz_end,ierr)
if (ierr .ne. CG_OK) call cgp_error_exit_f

! Set start and end points
this%start_n(1) = int(1, cgsize_t)
this%start_n(2) = int(1, cgsize_t)
this%start_n(3) = int((nz-1)*coord + 1, cgsize_t)
this%end_n(1) = int(nx, cgsize_t)
this%end_n(2) = int(ny, cgsize_t)
this%end_n(3) = int((nz-1)*coord + this%nz_end, cgsize_t)

! Write local x-mesh
allocate(xyz(nx, ny, this%nz_end))
do i = 1, nx
    xyz(i,:,:) = x(i)
end do
call cgp_coord_write_data_f(this%fid, this%base, this%zone, 1, this%start_n,   &
    this%end_n, xyz(1:nx,1:ny,1:this%nz_end), ierr)
if (ierr .ne. CG_OK) call cgp_error_exit_f

! Write local y-mesh
do i = 1, ny
    xyz(:,i,:) = y(i)
end do
call cgp_coord_write_data_f(this%fid, this%base, this%zone, 2, this%start_n,   &
    this%end_n, xyz(1:nx,1:ny,1:this%nz_end), ierr)
if (ierr .ne. CG_OK) call cgp_error_exit_f

! Write local z-mesh
do i = 1, this%nz_end
    xyz(:,:,i) = z(i)
end do
call cgp_coord_write_data_f(this%fid, this%base, this%zone, 3, this%start_n,   &
    this%end_n, xyz(1:nx,1:ny,1:this%nz_end), ierr)
if (ierr .ne. CG_OK) call cgp_error_exit_f

! Create a centered solution
call cg_sol_write_f(this%fid, this%base, this%zone, 'Solution', Vertex,        &
    this%sol, ierr)
if (ierr .ne. CG_OK) call cgp_error_exit_f

#else
! Set subarray size
! Note: start array assumes zero indexing (as in C)
call mpi_type_create_subarray(3, (/ nx, ny, nz_tot /),                         &
    (/ nx, ny, this%nz_end /), (/ 0, 0,((coord*(nz-1))) /), MPI_ORDER_FORTRAN, &
    MPI_RPREC, this%subarray_t, ierr)
call mpi_type_commit(this%subarray_t, ierr)
#endif
#endif

end subroutine open_file

!*******************************************************************************
subroutine write_field(this, field, field_name)
!*******************************************************************************
use mpi
class(data_writer_t), intent(inout) :: this
real(rprec), intent(inout), dimension(:,:,:) :: field
character(*), intent(in) :: field_name
#ifdef PPMPI
integer(MPI_OFFSET_KIND) :: offset
#endif
#ifdef PPCGNS
integer :: i
integer :: sec
#endif

! Check record size
if (size(field, 1) /= this%nx .or. size(field, 2) /= this%ny .or.              &
    size(field, 3) /= nz) call error('data_writer_t%write_field',              &
    'Invalid record size')

! Check field counter
if (this%counter > this%num_fields) call error('data_write_t%write_field',     &
    'All records already recorded.')

#ifdef PPMPI
#ifdef PPCGNS
! Create the field
call cgp_field_write_f(this%fid, this%base, this%zone, this%sol, RealDouble,   &
    field_name, sec, ierr)
if (ierr .ne. CG_OK) call cgp_error_exit_f

! Write data field
call cgp_field_write_data_f(this%fid, this%base, this%zone, this%sol, sec,     &
    this%start_n, this%end_n, field(:,:,:this%nz_end), ierr)
if (ierr .ne. CG_OK) call cgp_error_exit_f
#else
! Set the offset for each record
offset = (this%counter-1)*this%nx*this%ny*nz_tot*rprec

! Tell each processor what view to take
call mpi_file_set_view(this%fid, offset, MPI_RPREC, this%subarray_t,&
    write_endian, MPI_INFO_NULL, ierr)

! Write data collectively
call mpi_file_write_all(this%fid, field(:,:,:this%nz_end),                     &
    this%nx*this%ny*this%nz_end, MPI_RPREC, MPI_STATUS_IGNORE, ierr)
#endif
#else
write(this%fid, rec=this%counter) field
#endif

! Increment counter
this%counter = this%counter+1

! Mark file as opened
this%opened = .true.

end subroutine write_field

!*******************************************************************************
subroutine close_file(this)
!*******************************************************************************
class(data_writer_t), intent(inout) :: this

! Close file if open
if (this%opened) then
#ifdef PPMPI
#ifdef PPCGNS
    ! Close the file
    call cgp_close_f(this%fid, ierr)
    if (ierr .ne. CG_OK) call cgp_error_exit_f
#else
    call mpi_file_close(this%fid, ierr)
#endif
#else
    close(this%fid)
#endif
    this%opened = .false.
end if

end subroutine close_file

end module data_writer