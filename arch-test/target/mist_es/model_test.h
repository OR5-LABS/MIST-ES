#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H

#define XLEN 32

#define RVMODEL_DATA_SECTION

#define RVMODEL_BOOT

#define RVMODEL_HALT \
  li t0, 1; \
  li t1, 0x20000000; \
  sw t0, 0(t1); \
  self_loop: j self_loop;

#define RVMODEL_DATA_BEGIN \
  .align 4; .global begin_signature; begin_signature:

#define RVMODEL_DATA_END \
  .align 4; .global end_signature; end_signature: \
  RVMODEL_DATA_SECTION

#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_SP, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_SP, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)

#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT

#endif // _COMPLIANCE_MODEL_H
