! Copyright (c) 2023, The Neko Authors
! All rights reserved.
!
! Redistribution and use in source and binary forms, with or without
! modification, are permitted provided that the following conditions
! are met:
!
!   * Redistributions of source code must retain the above copyright
!     notice, this list of conditions and the following disclaimer.
!
!   * Redistributions in binary form must reproduce the above
!     copyright notice, this list of conditions and the following
!     disclaimer in the documentation and/or other materials provided
!     with the distribution.
!
!   * Neither the name of the authors nor the names of its
!     contributors may be used to endorse or promote products derived
!     from this software without specific prior written permission.
!
! THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
! "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
! LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
! FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
! COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
! INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
! BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
! LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
! CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
! LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
! ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
! POSSIBILITY OF SUCH DAMAGE.
!
!> Implements the CPU kernel for the `smagorinsky_t` type.
module smagorinsky_cpu
  use num_types, only : rp
  use field_list, only : field_list_t
  use math, only : cadd, NEKO_EPS
  use scratch_registry, only : neko_scratch_registry
  use field_registry, only : neko_field_registry
  use field, only : field_t
  use operators, only : strain_rate
  use coefs, only : coef_t
  use gs_ops, only : GS_OP_ADD
  use math, only : col2
  implicit none
  private

  public :: smagorinsky_compute_cpu

contains

  !> Compute eddy viscosity on the CPU.
  !! @param t The time value.
  !! @param tstep The current time-step.
  !! @param coef SEM coefficients.
  !! @param nut The SGS viscosity array.
  !! @param delta The LES lengthscale.
  !! @param c_s The smagorinsky model constant
  subroutine smagorinsky_compute_cpu(t, tstep, coef, nut, delta, c_s)
    real(kind=rp), intent(in) :: t
    integer, intent(in) :: tstep
    type(coef_t), intent(in) :: coef
    type(field_t), intent(inout) :: nut
    type(field_t), intent(in) :: delta
    real(kind=rp), intent(in) :: c_s
    type(field_t), pointer :: u, v, w
    ! double of the strain rate tensor
    type(field_t), pointer :: s11_2, s22_2, s33_2, s12_2, s13_2, s23_2
    real(kind=rp) :: s_abs
    integer :: temp_indices(6)
    integer :: e, i
    
    u => neko_field_registry%get_field_by_name("u")
    v => neko_field_registry%get_field_by_name("v")
    w => neko_field_registry%get_field_by_name("u")

    call neko_scratch_registry%request_field(s11_2, temp_indices(1))
    call neko_scratch_registry%request_field(s22_2, temp_indices(2))
    call neko_scratch_registry%request_field(s33_2, temp_indices(3))
    call neko_scratch_registry%request_field(s12_2, temp_indices(4))
    call neko_scratch_registry%request_field(s13_2, temp_indices(5))
    call neko_scratch_registry%request_field(s23_2, temp_indices(6))

    ! Compute the strain rate tensor
    call strain_rate(s11_2%x, s22_2%x, s33_2%x, s12_2%x, s13_2%x, s23_2%x, u, v, w, coef)
    
    do e=1, coef%msh%nelv
       do i=1, coef%Xh%lxyz
          s_abs = sqrt(0.5_rp * (s11_2%x(i,1,1,e)*s11_2%x(i,1,1,e) + &
                                 s22_2%x(i,1,1,e)*s22_2%x(i,1,1,e) + &
                                 s33_2%x(i,1,1,e)*s33_2%x(i,1,1,e)) + &
                                (s12_2%x(i,1,1,e)*s12_2%x(i,1,1,e) + &
                                 s13_2%x(i,1,1,e)*s13_2%x(i,1,1,e) + &
                                 s23_2%x(i,1,1,e)*s23_2%x(i,1,1,e)))

          nut%x(i,1,1,e) = c_s**2 * delta%x(i,1,1,e)**2 * s_abs
       end do
    end do

    call coef%gs_h%op(nut%x, nut%dof%size(), GS_OP_ADD)
    call col2(nut%x, coef%mult, nut%dof%size())

    call neko_scratch_registry%relinquish_field(temp_indices)
  end subroutine smagorinsky_compute_cpu

end module smagorinsky_cpu

