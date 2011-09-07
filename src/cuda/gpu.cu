/*
 *  gpu_startup.cu
 *  new_quick
 *
 *  Created by Yipu Miao on 4/20/11.
 *  Copyright 2011 University of Florida. All rights reserved.
 *
 */

#include <stdio.h>

#include "gpu.h"

//-----------------------------------------------
// Set up specified device and be ready to ignite
//-----------------------------------------------
extern "C" void gpu_set_device_(int* gpu_dev_id)
{
    gpu->gpu_dev_id = *gpu_dev_id;
}

//-----------------------------------------------
// create gpu class
//-----------------------------------------------
extern "C" void gpu_startup_(void)
{
	PRINTDEBUG("BEGIN TO WARM UP")
#ifdef DEBUG
    debugFile = fopen("DEBUG", "w+");
#endif
    gpu = new gpu_type;
	PRINTDEBUG("CREATE NEW GPU")
}


//-----------------------------------------------
// Initialize the device
//-----------------------------------------------
extern "C" void gpu_init_(void)
{

    PRINTDEBUG("BEGIN TO INIT")

    int device = -1;
    int gpuCount = 0;
    cudaError_t status;
    cudaDeviceProp deviceProp;
    status = cudaGetDeviceCount(&gpuCount);
    PRINTERROR(status,"cudaGetDeviceCount gpu_init failed!");
    if (gpuCount == 0)
    {
        printf("NO CUDA-Enabled GPU FOUND.\n");
        cudaThreadExit();
        exit(-1);
    }
    
    cudaGetDeviceProperties(&deviceProp, gpu->gpu_dev_id);
    if ( (deviceProp.major >=2) || ((deviceProp.major == 1) && (deviceProp.minor == 3))) 
        device = gpu->gpu_dev_id;
    else {
        printf("SELECT GPU HAS CUDA SUPPORTING VERSION UNDER 1.3. EXITING. \n");
        cudaThreadExit();
        exit(-1);
    }
   
    if (device == -1) {
        printf("NO CUDA 1.3 SUPPORTED GPU IS FOUND\n");
        gpu_shutdown_();
        exit(-1);
    }

    status = cudaSetDevice(device);
    PRINTERROR(status, "cudaSetDevice gpu_init failed!");
    cudaThreadSynchronize();
    
    gpu->blocks = deviceProp.multiProcessorCount;
    if (deviceProp.major ==1) {
        switch (deviceProp.minor) {
            case 0:
            case 1:
            case 2:
            case 5:
                printf("GPU SM VERSION SHOULD BE HIGHER THAN 1.3\n");
                gpu_shutdown_();
                exit(-1);
                break;
            default:
                gpu -> sm_version         =   SM_13;
                gpu -> threadsPerBlock    =   SM_13_THREADS_PER_BLOCK;
                break;
        }
    }else {
        gpu -> sm_version               = SM_2X;
        gpu -> threadsPerBlock          = SM_2X_THREADS_PER_BLOCK;
    }

    PRINTDEBUG("FINISH INIT")

    return;
}

//-----------------------------------------------
// shutdonw gpu and terminate gpu calculation part
//-----------------------------------------------
extern "C" void gpu_shutdown_(void)
{
	PRINTDEBUG("BEGIN TO SHUTDOWN")
#ifdef DEBUG
    fclose(debugFile);
#endif
    delete gpu;
    cudaThreadExit();
	PRINTDEBUG("SHUTDOWN NORMALLY")
    return;
}

//-----------------------------------------------
//  Setup up basic infomation of the system
//-----------------------------------------------
extern "C" void gpu_setup_(int* natom, int* nbasis, int* nElec, int* imult, int* molchg, int* iAtomType)
{

#ifdef DEBUG
    cudaEvent_t start,end;
    cudaEventCreate(&start);
    cudaEventCreate(&end);
    cudaEventRecord(start, 0);
#endif

    PRINTDEBUG("BEGIN TO SETUP")

    gpu -> natom                    =   *natom;
    gpu -> nbasis                   =   *nbasis;
    gpu -> nElec                    =   *nElec;
    gpu -> imult                    =   *imult;
    gpu -> molchg                   =   *molchg;
    gpu -> iAtomType                =   *iAtomType;
    gpu -> gpu_calculated           =   new gpu_calculated_type;
    gpu -> gpu_basis                =   new gpu_basis_type;
    gpu -> gpu_cutoff               =   new gpu_cutoff_type;
    gpu -> gpu_calculated -> natom  =   *natom;
    gpu -> gpu_basis -> natom       =   *natom;
    gpu -> gpu_calculated -> nbasis =   *nbasis;
    gpu -> gpu_basis -> nbasis      =   *nbasis;
    
    gpu -> gpu_sim.natom            =   *natom;
    gpu -> gpu_sim.nbasis           =   *nbasis;
    gpu -> gpu_sim.nElec            =   *nElec;
    gpu -> gpu_sim.imult            =   *imult;
    gpu -> gpu_sim.molchg           =   *molchg;
    gpu -> gpu_sim.iAtomType        =   *iAtomType;

	upload_para_to_const();

#ifdef DEBUG
    cudaEventRecord(end, 0);
    cudaEventSynchronize(end);
    float time;
    cudaEventElapsedTime(&time, start, end);
    PRINTUSINGTIME("UPLOAD PARA TO CONST",time);
    cudaEventDestroy(start);
    cudaEventDestroy(end);
#endif

    PRINTDEBUG("FINISH SETUP")    
}

//-----------------------------------------------
//  upload coordinates
//-----------------------------------------------
extern "C" void gpu_upload_xyz_(QUICKDouble* atom_xyz)
{
#ifdef DEBUG
    cudaEvent_t start,end;
    cudaEventCreate(&start);
    cudaEventCreate(&end);
    cudaEventRecord(start, 0);
#endif

    PRINTDEBUG("BEGIN TO UPLOAD COORDINATES")
//    gpu -> gpu_basis -> xyz = new cuda_buffer_type<QUICKDouble>(atom_xyz, 3, gpu->natom);
//	gpu -> gpu_basis -> xyz ->Upload();
    gpu -> gpu_calculated -> distance = new cuda_buffer_type<QUICKDouble>(gpu->natom, gpu->natom);

    gpu -> xyz = new cuda_buffer_type<QUICKDouble>(atom_xyz, 3, gpu->natom);
    gpu -> xyz -> Upload();
    

    gpu -> gpu_sim.xyz =  gpu -> xyz -> _devData;

#ifdef DEBUG
    cudaEventRecord(end, 0);
    cudaEventSynchronize(end);
    float time;
    cudaEventElapsedTime(&time, start, end);
    PRINTUSINGTIME("UPLOAD XYZ",time);
    cudaEventDestroy(start);
    cudaEventDestroy(end);
#endif

    PRINTDEBUG("COMPLETE UPLOADING COORDINATES")

}


//-----------------------------------------------
//  upload molecule infomation
//-----------------------------------------------
extern "C" void gpu_upload_atom_and_chg_(int* atom, QUICKDouble* atom_chg)
{

    PRINTDEBUG("BEGIN TO UPLOAD ATOM AND CHARGE")
/*    
    gpu -> iattype = new cuda_buffer_type<int>(atom, gpu->natom);
    gpu -> chg     = new cuda_buffer_type<QUICKDouble>(atom_chg, gpu->natom);
    gpu -> iattype -> Upload();
    gpu -> chg     -> Upload();
*/
    PRINTDEBUG("COMPLETE UPLOADING ATOM AND CHARGE")
}


//-----------------------------------------------
//  upload cutoff criteria, will update every 
//  interation
//-----------------------------------------------
extern "C" void gpu_upload_cutoff_(QUICKDouble* cutMatrix, QUICKDouble* integralCutoff,QUICKDouble* primLimit)
{

#ifdef DEBUG
    cudaEvent_t start,end;
    cudaEventCreate(&start);
    cudaEventCreate(&end);
    cudaEventRecord(start, 0);
#endif

    PRINTDEBUG("BEGIN TO UPLOAD CUTOFF")
    
    gpu -> gpu_cutoff -> integralCutoff = *integralCutoff;
    gpu -> gpu_cutoff -> primLimit  = *primLimit;
    gpu -> gpu_cutoff -> cutMatrix  = new cuda_buffer_type<QUICKDouble>(cutMatrix, gpu->nshell, gpu->nshell);
    
    gpu -> gpu_cutoff -> cutMatrix  -> Upload();

    gpu -> gpu_sim.cutMatrix        = gpu -> gpu_cutoff -> cutMatrix -> _devData;
    gpu -> gpu_sim.integralCutoff   = gpu -> gpu_cutoff -> integralCutoff;
    gpu -> gpu_sim.primLimit        = gpu -> gpu_cutoff -> primLimit;

#ifdef DEBUG
    cudaEventRecord(end, 0);
    cudaEventSynchronize(end);
    float time;
    cudaEventElapsedTime(&time, start, end);
    PRINTUSINGTIME("UPLOAD CUTOFF",time);
    cudaEventDestroy(start);
    cudaEventDestroy(end);
#endif

    PRINTDEBUG("COMPLETE UPLOADING CUTOFF")
}


//-----------------------------------------------
//  upload cutoff matrix, only update at first
//  interation
//-----------------------------------------------
extern "C" void gpu_upload_cutoff_matrix_(QUICKDouble* YCutoff,QUICKDouble* cutPrim)
{

#ifdef DEBUG
    cudaEvent_t start,end;
    cudaEventCreate(&start);
    cudaEventCreate(&end);
    cudaEventRecord(start, 0);
#endif

    PRINTDEBUG("BEGIN TO UPLOAD CUTOFF")
    
    gpu -> gpu_cutoff -> natom      = gpu -> natom;
    gpu -> gpu_cutoff -> YCutoff    = new cuda_buffer_type<QUICKDouble>(YCutoff, gpu->nshell, gpu->nshell);
    gpu -> gpu_cutoff -> cutPrim    = new cuda_buffer_type<QUICKDouble>(cutPrim, gpu->jbasis, gpu->jbasis);
    
    gpu -> gpu_cutoff -> YCutoff    -> Upload();
    gpu -> gpu_cutoff -> cutPrim    -> Upload();
    
    gpu -> gpu_cutoff -> sqrQshell  = (gpu -> gpu_basis -> Qshell) * (gpu -> gpu_basis -> Qshell);
    gpu -> gpu_cutoff -> sorted_YCutoffIJ           = new cuda_buffer_type<int2>(gpu->gpu_cutoff->sqrQshell);
    
    
    int a = 0;
    bool flag = true;
    int2 temp; 
    
    
    for (int i = 0; i < gpu->gpu_basis->Qshell; i++) {
        for (int j = 0; j<gpu->gpu_basis->Qshell; j++) {
            //if (gpu->gpu_basis->sorted_Qnumber->_hostData[i] == q && gpu->gpu_basis->sorted_Qnumber->_hostData[j] == p) {
            if (LOC2(YCutoff, gpu->gpu_basis->sorted_Q->_hostData[i], gpu->gpu_basis->sorted_Q->_hostData[j], gpu->nshell, gpu->nshell) > 1E-9 && 
                gpu->gpu_basis->sorted_Q->_hostData[i] <= gpu->gpu_basis->sorted_Q->_hostData[j]) {
                gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[a].x = i;
                gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[a].y = j;
                a++;
            }
            //}
        }
    }    
    
    
//    for (int q = 0; q <= 1; q++) {
//    for (int p = 0; p <= 1; q++) {

    for (int i = 0; i < a - 1; i ++)
    {
        flag = true;
        for (int j = 0; j < a - i - 1; j ++)
        {
            if ((LOC2(YCutoff, gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j].x], \
                      gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j].y], gpu->nshell, gpu->nshell) < \
                 LOC2(YCutoff, gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j+1].x], \
                      gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j+1].y], gpu->nshell, gpu->nshell)))
            //&&   gpu->gpu_basis->sorted_Qnumber->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j+1].x] == q &&  \
            //     gpu->gpu_basis->sorted_Qnumber->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j+1].y]== p &&  \
            //     gpu->gpu_basis->sorted_Qnumber->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j].x] == q && \
            //     gpu->gpu_basis->sorted_Qnumber->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j].y] == p )
            {
                temp = gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j];
                gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j] = gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j + 1];
                gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j + 1] = temp;
                flag = false;
            }
        } 
        
        if (flag == true)
        break;
    }
    
    flag = true;
    
    for (int i = 0; i < a - 1; i ++)
    {
        flag = true;
        for (int j = 0; j < a - i - 1; j ++)
        {
            if ( gpu->gpu_basis->kprim->_hostData[gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j].x]] *
                 gpu->gpu_basis->kprim->_hostData[gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j].y]] <
                 gpu->gpu_basis->kprim->_hostData[gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j+1].x]] *
                 gpu->gpu_basis->kprim->_hostData[gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j+1].y]])
            {
                temp = gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j];
                gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j] = gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j + 1];
                gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j + 1] = temp;
                flag = false;
            }else if (gpu->gpu_basis->kprim->_hostData[gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j].x]] *
                      gpu->gpu_basis->kprim->_hostData[gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j].y]] ==
                      gpu->gpu_basis->kprim->_hostData[gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j+1].x]] *
                      gpu->gpu_basis->kprim->_hostData[gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j+1].y]])
            {
                if (gpu->gpu_basis->kprim->_hostData[gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j].x]]<
                    gpu->gpu_basis->kprim->_hostData[gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j+1].x]]) {
                    temp = gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j];
                    gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j] = gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j + 1];
                    gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[j + 1] = temp;
                    flag = false;
                }
            }
        } 
        
        if (flag == true)
        break;
    }
    
    flag = true;
//}
//}
    

    printf("a = %i, total = %i, pect= %f\n", a, gpu->gpu_basis->Qshell * (gpu->gpu_basis->Qshell+1)/2, (float)a/(gpu->gpu_basis->Qshell*(gpu->gpu_basis->Qshell)));
        
    gpu->gpu_cutoff->sqrQshell  = a;
    
    
    printf("SS = %i\n",a);
    for (int i = 0; i<a; i++) {
        printf("%8i %4i %4i %18.13f Q=%4i %4i %4i %4i prim = %4i %4i\n", i, \
        gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[i].x, \
        gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[i].y, \
        LOC2(YCutoff, gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[i].x], gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[i].y], gpu->nshell, gpu->nshell),\
        gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[i].x], \
        gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[i].y], \
        gpu->gpu_basis->sorted_Qnumber->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[i].x], \
        gpu->gpu_basis->sorted_Qnumber->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[i].y], \
        gpu->gpu_basis->kprim->_hostData[gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[i].x]],
        gpu->gpu_basis->kprim->_hostData[gpu->gpu_basis->sorted_Q->_hostData[gpu->gpu_cutoff->sorted_YCutoffIJ ->_hostData[i].y]]);
    }
    
    gpu -> gpu_cutoff -> sorted_YCutoffIJ  -> Upload();
    gpu -> gpu_sim.sqrQshell        = gpu -> gpu_cutoff -> sqrQshell;
    gpu -> gpu_sim.YCutoff          = gpu -> gpu_cutoff -> YCutoff -> _devData;
    gpu -> gpu_sim.cutPrim          = gpu -> gpu_cutoff -> cutPrim -> _devData;
    gpu -> gpu_sim.sorted_YCutoffIJ = gpu -> gpu_cutoff -> sorted_YCutoffIJ  -> _devData;
    
    
    
#ifdef DEBUG
    cudaEventRecord(end, 0);
    cudaEventSynchronize(end);
    float time;
    cudaEventElapsedTime(&time, start, end);
    PRINTUSINGTIME("UPLOAD CUTOFF",time);
    cudaEventDestroy(start);
    cudaEventDestroy(end);
#endif

    PRINTDEBUG("COMPLETE UPLOADING CUTOFF")
}

//-----------------------------------------------
//  upload calculated information
//-----------------------------------------------
extern "C" void gpu_upload_calculated_(QUICKDouble* o, QUICKDouble* co, QUICKDouble* vec, QUICKDouble* dense)
{

#ifdef DEBUG
    cudaEvent_t start,end;
    cudaEventCreate(&start);
    cudaEventCreate(&end);
    cudaEventRecord(start, 0);
#endif

    PRINTDEBUG("BEGIN TO UPLOAD O MATRIX")
    
    gpu -> gpu_calculated -> o        =   new cuda_buffer_type<QUICKDouble>(o,      gpu->nbasis, gpu->nbasis);
    gpu -> gpu_calculated -> dense    =   new cuda_buffer_type<QUICKDouble>(dense,  gpu->nbasis, gpu->nbasis);
    gpu -> gpu_calculated -> oULL     =   new cuda_buffer_type<QUICKULL>(gpu->nbasis, gpu->nbasis);
    
    
    /*
        oULL is the unsigned long long int type of O matrix. The reason to do so is because 
        Atomic Operator for CUDA 2.0 is only available for integer. So for double precision type, 
        an comprimise way is to multiple a very large number (OSCALE), first and divided it
        after atomic operator.
     */
    for (int i = 0; i<gpu->nbasis; i++) {
        for (int j = 0; j<gpu->nbasis; j++) {
            QUICKULL valUII = (QUICKULL) (fabs ( LOC2( gpu->gpu_calculated->o->_hostData, i, j, gpu->nbasis, gpu->nbasis)*OSCALE + (QUICKDouble)0.5));

            if (LOC2( gpu->gpu_calculated->o->_hostData, i, j, gpu->nbasis, gpu->nbasis)<(QUICKDouble)0.0)
            {
                valUII = 0ull - valUII;
            }
            
            LOC2( gpu->gpu_calculated->oULL->_hostData, i, j, gpu->nbasis, gpu->nbasis) = valUII;
        }
    }
    
    gpu -> gpu_calculated -> o        -> Upload();
    gpu -> gpu_calculated -> dense    -> Upload();
    gpu -> gpu_calculated -> oULL     -> Upload();
    
    gpu -> gpu_sim.o                 =  gpu -> gpu_calculated -> o -> _devData;
    gpu -> gpu_sim.dense             =  gpu -> gpu_calculated -> dense -> _devData;
    gpu -> gpu_sim.oULL              =  gpu -> gpu_calculated -> oULL -> _devData;
    
    
#ifdef DEBUG
    cudaEventRecord(end, 0);
    cudaEventSynchronize(end);
    float time;
    cudaEventElapsedTime(&time, start, end);
    PRINTUSINGTIME("UPLOAD CALCULATE",time);
    cudaEventDestroy(start);
    cudaEventDestroy(end);
#endif

    PRINTDEBUG("COMPLETE UPLOADING O MATRIX")
}

//-----------------------------------------------
//  upload basis set information
//-----------------------------------------------
extern "C" void gpu_upload_basis_(int* nshell, int* nprim, int* jshell, int* jbasis, int* maxcontract, \
int* ncontract, int* itype,     QUICKDouble* aexp,      QUICKDouble* dcoeff,\
int* first_basis_function, int* last_basis_function, int* first_shell_basis_function, int* last_shell_basis_function, \
int* ncenter,   int* kstart,    int* katom,     int* ktype,     int* kprim,  int* kshell, int* Ksumtype, \
int* Qnumber,   int* Qstart,    int* Qfinal,    int* Qsbasis,   int* Qfbasis,\
QUICKDouble* gccoeff,           QUICKDouble* cons,      QUICKDouble* gcexpo, int* KLMN)
{

#ifdef DEBUG
    cudaEvent_t start,end;
    cudaEventCreate(&start);
    cudaEventCreate(&end);
    cudaEventRecord(start, 0);
#endif

    PRINTDEBUG("BEGIN TO UPLOAD BASIS")
    
    gpu -> gpu_basis -> nshell          =   *nshell;
    gpu -> gpu_basis -> nprim           =   *nprim;
    gpu -> gpu_basis -> jshell          =   *jshell;
    gpu -> gpu_basis -> jbasis          =   *jbasis;
    gpu -> gpu_basis -> maxcontract     =   *maxcontract;
    
    gpu -> nshell                       =   *nshell;
    gpu -> nprim                        =   *nprim;
    gpu -> jshell                       =   *jshell;
    gpu -> jbasis                       =   *jbasis;

    gpu -> gpu_sim.nshell                   =   *nshell;
    gpu -> gpu_sim.nprim                    =   *nprim;
    gpu -> gpu_sim.jshell                   =   *jshell;
    gpu -> gpu_sim.jbasis                   =   *jbasis;
    gpu -> gpu_sim.maxcontract              =   *maxcontract;

/*
    gpu -> gpu_basis -> ncontract                   =   new cuda_buffer_type<int>(ncontract, 1);//gpu->nbasis);
    gpu -> gpu_basis -> itype                       =   new cuda_buffer_type<int>(itype, 1);//3, gpu->nbasis);
    gpu -> gpu_basis -> aexp                        =   new cuda_buffer_type<QUICKDouble>(aexp, 1);//gpu->gpu_basis->maxcontract, gpu->nbasis);
    gpu -> gpu_basis -> dcoeff                      =   new cuda_buffer_type<QUICKDouble>(dcoeff, 1);//gpu->gpu_basis->maxcontract, gpu->nbasis);

    gpu -> gpu_basis -> first_basis_function        =   new cuda_buffer_type<int>(first_basis_function, 1);//gpu->natom);
    gpu -> gpu_basis -> last_basis_function         =   new cuda_buffer_type<int>(last_basis_function,  1);//gpu->natom);

    gpu -> gpu_basis -> first_shell_basis_function  =   new cuda_buffer_type<int>(first_shell_basis_function, 1);//gpu->gpu_basis->nshell);
    gpu -> gpu_basis -> last_shell_basis_function   =   new cuda_buffer_type<int>(last_shell_basis_function,  1);//gpu->gpu_basis->nshell);
    gpu -> gpu_basis -> ncenter                     =   new cuda_buffer_type<int>(ncenter,                    gpu->gpu_basis->nbasis);
*/
    gpu -> gpu_basis -> kstart                      =   new cuda_buffer_type<int>(kstart,   gpu->gpu_basis->nshell);
    gpu -> gpu_basis -> katom                       =   new cuda_buffer_type<int>(katom,    gpu->gpu_basis->nshell);
//    gpu -> gpu_basis -> ktype                       =   new cuda_buffer_type<int>(ktype,    gpu->gpu_basis->nshell);
    gpu -> gpu_basis -> kprim                       =   new cuda_buffer_type<int>(kprim,    gpu->gpu_basis->nshell);
//    gpu -> gpu_basis -> kshell                      =   new cuda_buffer_type<int>(kshell,   93);
    gpu -> gpu_basis -> Ksumtype                    =   new cuda_buffer_type<int>(Ksumtype, gpu->gpu_basis->nshell+1);

    gpu -> gpu_basis -> Qnumber                     =   new cuda_buffer_type<int>(Qnumber,  gpu->gpu_basis->nshell);
    gpu -> gpu_basis -> Qstart                      =   new cuda_buffer_type<int>(Qstart,   gpu->gpu_basis->nshell);
    gpu -> gpu_basis -> Qfinal                      =   new cuda_buffer_type<int>(Qfinal,   gpu->gpu_basis->nshell);
    gpu -> gpu_basis -> Qsbasis                     =   new cuda_buffer_type<int>(Qsbasis,  gpu->gpu_basis->nshell, 4);
    gpu -> gpu_basis -> Qfbasis                     =   new cuda_buffer_type<int>(Qfbasis,  gpu->gpu_basis->nshell, 4);
    gpu -> gpu_basis -> gccoeff                     =   new cuda_buffer_type<QUICKDouble>(gccoeff, 6, gpu->nbasis);

    gpu -> gpu_basis -> cons                        =   new cuda_buffer_type<QUICKDouble>(cons, gpu->nbasis);
    gpu -> gpu_basis -> gcexpo                      =   new cuda_buffer_type<QUICKDouble>(gcexpo, 6, gpu->nbasis);
    gpu -> gpu_basis -> KLMN                        =   new cuda_buffer_type<int>(KLMN, 3, gpu->nbasis);
    
    gpu -> gpu_basis -> Xcoeff                      =   new cuda_buffer_type<QUICKDouble>(4*gpu->jbasis, 4*gpu->jbasis);
    gpu -> gpu_basis -> expoSum                     =   new cuda_buffer_type<QUICKDouble>(6*gpu->jshell, 6*gpu->jshell);
    gpu -> gpu_basis -> weightedCenterX             =   new cuda_buffer_type<QUICKDouble>(6*gpu->jshell, 6*gpu->jshell);
    gpu -> gpu_basis -> weightedCenterY             =   new cuda_buffer_type<QUICKDouble>(6*gpu->jshell, 6*gpu->jshell);
    gpu -> gpu_basis -> weightedCenterZ             =   new cuda_buffer_type<QUICKDouble>(6*gpu->jshell, 6*gpu->jshell);
    
    
    /*
        After uploading basis set information, we want to do some more things on CPU so that will accelarate GPU.
        The very first is to sort orbital type. In this case, we will calculate s orbitals then p, d, and etc.
        Here Qshell is the number of shell orbtials, for example, sp orbitals account for 2 shell orbitals, and s orbital accounts
        1 shell orbital.
     */
    gpu->gpu_basis->Qshell = 0;
    for (int i = 0; i<gpu->nshell; i++) {
        gpu->gpu_basis->Qshell += gpu->gpu_basis->Qfinal->_hostData[i] - gpu->gpu_basis->Qstart->_hostData[i] + 1;
    }
    
    gpu -> gpu_sim.Qshell = gpu->gpu_basis->Qshell;
    
    gpu -> gpu_basis -> sorted_Q                    =   new cuda_buffer_type<int>( gpu->gpu_basis->Qshell);
    gpu -> gpu_basis -> sorted_Qnumber              =   new cuda_buffer_type<int>( gpu->gpu_basis->Qshell);
    
    /*
        Now because to sort, sorted_Q stands for the shell no, and sorted_Qnumber is the shell orbital type (or angular momentum).
        For instance:
        
        original: s sp s s s sp s s
        sorteed : s s  s s s s  s s p p
        
        move p orbital to the end of the sequence. so the Qshell stands for the length of sequence after sorting.
     */
    int a = 0;
    for (int i = 0; i<gpu->gpu_basis->nshell; i++) {
        for (int j = gpu->gpu_basis->Qstart->_hostData[i]; j<= gpu->gpu_basis->Qfinal->_hostData[i]; j++) {

            if (a == 0) {
                gpu->gpu_basis->sorted_Q->_hostData[0] = i;
                gpu->gpu_basis->sorted_Qnumber->_hostData[0] = j;
            }else {
                for (int k = 0; k<a; k++) {
                    if (j<gpu->gpu_basis->sorted_Qnumber->_hostData[k]) {
                    
                        int kk = k;
                        for (int l = a; l> kk; l--) {
                            gpu->gpu_basis->sorted_Q->_hostData[l] = gpu->gpu_basis->sorted_Q->_hostData[l-1];
                            gpu->gpu_basis->sorted_Qnumber->_hostData[l] = gpu->gpu_basis->sorted_Qnumber->_hostData[l-1];
                        }
                        
                        gpu->gpu_basis->sorted_Q->_hostData[kk] = i;
                        gpu->gpu_basis->sorted_Qnumber->_hostData[kk] = j;
                        break;
                    }
                    gpu->gpu_basis->sorted_Q->_hostData[a] = i;
                    gpu->gpu_basis->sorted_Qnumber->_hostData[a] = j;
                }
            }
            a++;
        }
    }
    
    
    
    /*
    for (int i = 0; i<gpu->gpu_basis->Qshell; i++) {
        for (int j = i; j<gpu->gpu_basis->Qshell; j++) {
            if (gpu->gpu_basis->sorted_Qnumber->_hostData[i] == gpu->gpu_basis->sorted_Qnumber->_hostData[j]) {
                if (gpu->gpu_basis->kprim->_hostData[gpu->gpu_basis->sorted_Q->_hostData[i]] < gpu->gpu_basis->kprim->_hostData[gpu->gpu_basis->sorted_Q->_hostData[j]]) {
                    int temp = gpu->gpu_basis->sorted_Q->_hostData[j];
                    gpu->gpu_basis->sorted_Q->_hostData[j] = gpu->gpu_basis->sorted_Q->_hostData[i];
                    gpu->gpu_basis->sorted_Q->_hostData[i] = temp;
                }
            }
        }
    }*/
    
    printf("Pre-Sorted orbitals:\n");
    printf("Qshell = %i\n", gpu->gpu_basis->Qshell);
    for (int i = 0; i<gpu->gpu_basis->Qshell; i++) {
        printf("i= %i, Q=%i, Qnumber= %i, nprim = %i \n", i, gpu->gpu_basis->sorted_Q->_hostData[i], gpu->gpu_basis->sorted_Qnumber->_hostData[i],
                                                             gpu->gpu_basis->kprim->_hostData[gpu->gpu_basis->sorted_Q->_hostData[i]]);
    }
    
    
    /*
        some pre-calculated variables includes
        
        expoSum(i,j) = expo(i)+expo(j)
        ------------->                 ->          ->
        weightedCenter(i,j) = (expo(i)*i + expo(j)*j)/(expo(i)+expo(j))
     */
    for (int i = 0; i<gpu->jshell; i++) {
        for (int j = 0; j<gpu->jshell; j++) {
            int kAtomI = gpu->gpu_basis->katom->_hostData[i];
            int kAtomJ = gpu->gpu_basis->katom->_hostData[j];
            int KsumtypeI = gpu->gpu_basis->Ksumtype->_hostData[i];
            int KsumtypeJ = gpu->gpu_basis->Ksumtype->_hostData[j];
            int kstartI = gpu->gpu_basis->kstart->_hostData[i];
            int kstartJ = gpu->gpu_basis->kstart->_hostData[j];
            
            QUICKDouble distance = 0;
            for (int k = 0; k<3; k++) {
                    distance += pow(LOC2(gpu->xyz->_hostData, k, kAtomI-1, 3, gpu->natom)
                                   -LOC2(gpu->xyz->_hostData, k, kAtomJ-1, 3, gpu->natom),2);
            }
            
            QUICKDouble DIJ = distance;
            
            for (int ii = 0; ii<gpu->gpu_basis->kprim->_hostData[i]; ii++) {
                for (int jj = 0; jj<gpu->gpu_basis->kprim->_hostData[j]; jj++) {
                    
                    QUICKDouble II = LOC2(gpu->gpu_basis->gcexpo->_hostData, ii , KsumtypeI-1, 6, gpu->nbasis);
                    QUICKDouble JJ = LOC2(gpu->gpu_basis->gcexpo->_hostData, jj , KsumtypeJ-1, 6, gpu->nbasis);
                    
                    //expoSum(i,j) = expo(i)+expo(j)
                    LOC4(gpu->gpu_basis->expoSum->_hostData, ii, jj, i, j, 6, 6, gpu->jshell, gpu->jshell) = II + JJ;
                    
                    
                    //        ------------->                 ->          ->
                    //        weightedCenter(i,j) = (expo(i)*i + expo(j)*j)/(expo(i)+expo(j))
                    LOC4(gpu->gpu_basis->weightedCenterX->_hostData, ii, jj, i, j, 6, 6, gpu->jshell, gpu->jshell) = \
                        (LOC2(gpu->xyz->_hostData, 0, kAtomI-1, 3, gpu->natom) * II + LOC2(gpu->xyz->_hostData, 0, kAtomJ-1, 3, gpu->natom)*JJ)/(II+JJ);
                    LOC4(gpu->gpu_basis->weightedCenterY->_hostData, ii, jj, i, j, 6, 6, gpu->jshell, gpu->jshell) = \
                        (LOC2(gpu->xyz->_hostData, 1, kAtomI-1, 3, gpu->natom) * II + LOC2(gpu->xyz->_hostData, 1, kAtomJ-1, 3, gpu->natom)*JJ)/(II+JJ);
                    LOC4(gpu->gpu_basis->weightedCenterZ->_hostData, ii, jj, i, j, 6, 6, gpu->jshell, gpu->jshell) = \
                        (LOC2(gpu->xyz->_hostData, 2, kAtomI-1, 3, gpu->natom) * II + LOC2(gpu->xyz->_hostData, 2, kAtomJ-1, 3, gpu->natom)*JJ)/(II+JJ);
                    
                    
                    // Xcoeff = exp(-II*JJ/(II+JJ) * DIJ) / (II+JJ) * coeff(i) * coeff(j) * X0
                    QUICKDouble X = exp(-II*JJ/(II+JJ)*DIJ)/(II+JJ);
                    for (int itemp = gpu->gpu_basis->Qstart->_hostData[i]; itemp <= gpu->gpu_basis->Qfinal->_hostData[i]; itemp++) {
                        for (int itemp2 = gpu->gpu_basis->Qstart->_hostData[j]; itemp2 <= gpu->gpu_basis->Qfinal->_hostData[j]; itemp2++) {
                            LOC4(gpu->gpu_basis->Xcoeff->_hostData, kstartI+ii-1, kstartJ+jj-1, itemp, itemp2, gpu->jbasis, gpu->jbasis, 4, 4)
                            = X0 * X * LOC2(gpu->gpu_basis->gccoeff->_hostData, ii, KsumtypeI+itemp-1, 6, gpu->nbasis) \
                                     * LOC2(gpu->gpu_basis->gccoeff->_hostData, jj, KsumtypeJ+itemp2-1, 6, gpu->nbasis);
                        }
                    }
                }
            }
        }
    }
    
    gpu -> gpu_basis -> upload_all();


    gpu -> gpu_sim.expoSum                      =   gpu -> gpu_basis -> expoSum -> _devData;
    gpu -> gpu_sim.weightedCenterX              =   gpu -> gpu_basis -> weightedCenterX -> _devData;
    gpu -> gpu_sim.weightedCenterY              =   gpu -> gpu_basis -> weightedCenterY -> _devData;
    gpu -> gpu_sim.weightedCenterZ              =   gpu -> gpu_basis -> weightedCenterZ -> _devData;
    gpu -> gpu_sim.sorted_Q                     =   gpu -> gpu_basis -> sorted_Q -> _devData;
    gpu -> gpu_sim.sorted_Qnumber               =   gpu -> gpu_basis -> sorted_Qnumber -> _devData;
     
    gpu -> gpu_sim.Xcoeff                       =   gpu -> gpu_basis -> Xcoeff -> _devData;
/*
    gpu -> gpu_sim.ncontract                    =   gpu -> gpu_basis -> ncontract -> _devData;
    gpu -> gpu_sim.first_basis_function         =   gpu -> gpu_basis -> first_basis_function -> _devData;
    gpu -> gpu_sim.last_basis_function          =   gpu -> gpu_basis -> last_basis_function -> _devData;
    gpu -> gpu_sim.first_shell_basis_function   =   gpu -> gpu_basis -> first_shell_basis_function -> _devData;
    gpu -> gpu_sim.last_shell_basis_function    =   gpu -> gpu_basis -> last_shell_basis_function -> _devData;
    gpu -> gpu_sim.ncenter                      =   gpu -> gpu_basis -> ncenter -> _devData;
    gpu -> gpu_sim.ktype                        =   gpu -> gpu_basis -> ktype -> _devData;
    gpu -> gpu_sim.kshell                       =   gpu -> gpu_basis -> kshell -> _devData;
  */
    gpu -> gpu_sim.kstart                       =   gpu -> gpu_basis -> kstart -> _devData;    
    gpu -> gpu_sim.katom                        =   gpu -> gpu_basis -> katom -> _devData;
    gpu -> gpu_sim.kprim                        =   gpu -> gpu_basis -> kprim -> _devData;    
    gpu -> gpu_sim.Ksumtype                     =   gpu -> gpu_basis -> Ksumtype -> _devData;
    gpu -> gpu_sim.Qnumber                      =   gpu -> gpu_basis -> Qnumber -> _devData;
    gpu -> gpu_sim.Qstart                       =   gpu -> gpu_basis -> Qstart -> _devData;
    gpu -> gpu_sim.Qfinal                       =   gpu -> gpu_basis -> Qfinal -> _devData;    
    gpu -> gpu_sim.Qsbasis                      =   gpu -> gpu_basis -> Qsbasis -> _devData;
    gpu -> gpu_sim.Qfbasis                      =   gpu -> gpu_basis -> Qfbasis -> _devData;
    gpu -> gpu_sim.gccoeff                      =   gpu -> gpu_basis -> gccoeff -> _devData;
    gpu -> gpu_sim.cons                         =   gpu -> gpu_basis -> cons -> _devData;
    gpu -> gpu_sim.gcexpo                       =   gpu -> gpu_basis -> gcexpo -> _devData;
    gpu -> gpu_sim.KLMN                         =   gpu -> gpu_basis -> KLMN -> _devData;    

#ifdef DEBUG
    cudaEventRecord(end, 0);
    cudaEventSynchronize(end);
    float time;
    cudaEventElapsedTime(&time, start, end);
    PRINTUSINGTIME("UPLOAD BASIS",time);
    cudaEventDestroy(start);
    cudaEventDestroy(end);
#endif

    PRINTDEBUG("COMPLETE UPLOADING BASIS")
}


//-----------------------------------------------
//  core part, compute 2-e integrals
//-----------------------------------------------
extern "C" void gpu_get2e_(QUICKDouble* o)
{
    PRINTDEBUG("BEGIN TO RUN GET2E")

    upload_sim_to_constant(gpu);

    PRINTDEBUG("BEGIN TO RUN KERNEL") 

    get2e(gpu);

    PRINTDEBUG("COMPLETE KERNEL")
    gpu -> gpu_calculated -> oULL -> Download();
    
    for (int i = 0; i< gpu->nbasis; i++) {
        for (int j = i; j< gpu->nbasis; j++) {
            QUICKULL valULL = LOC2(gpu->gpu_calculated->oULL->_hostData, j, i, gpu->nbasis, gpu->nbasis);
            QUICKDouble valDB;
            
            if (valULL >= 0x8000000000000000ull) {
                valDB  = -(QUICKDouble)(valULL ^ 0xffffffffffffffffull);
            }
            else
            {
                valDB  = (QUICKDouble) valULL;
            }
            LOC2(gpu->gpu_calculated->o->_hostData,i,j,gpu->nbasis, gpu->nbasis) = (QUICKDouble)valDB*ONEOVEROSCALE;
            LOC2(gpu->gpu_calculated->o->_hostData,j,i,gpu->nbasis, gpu->nbasis) = (QUICKDouble)valDB*ONEOVEROSCALE;
        }
    }
    
    gpu -> gpu_calculated -> o    -> Download(o);

    PRINTDEBUG("DELETE TEMP VARIABLES")
	
	delete gpu->gpu_calculated->o;
	delete gpu->gpu_calculated->dense;
	delete gpu->gpu_calculated->oULL;

    PRINTDEBUG("COMPLETE RUNNING GET2E")
}
