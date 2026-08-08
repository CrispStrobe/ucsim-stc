/*
 * Simulator of microcontrollers (s51.src/stc12_pcacl.h)
 *
 * STC12 PCA with correct clock prescaling for 1T CPU.
 *
 * Copyright (C) 2024 CrispStrobe
 *
 */

#ifndef STC12_PCACL_HEADER
#define STC12_PCACL_HEADER

/* Work around pcacl.h's broken include guard (shares PORTCL_HEADER
   with portcl.h).  If portcl.h was already included, pcacl.h would
   be silently skipped. */
#ifdef PORTCL_HEADER
#undef PORTCL_HEADER
#include "pcacl.h"
#define PORTCL_HEADER
#else
#include "pcacl.h"
#endif

class cl_pca_stc12: public cl_pca
{
protected:
  int pca_prescaler; /* accumulates ticks for FOSC/12 source */
public:
  cl_pca_stc12(class cl_uc *auc, int aid);
  virtual int tick(int cycles);
};


#endif

/* End of s51.src/stc12_pcacl.h */
