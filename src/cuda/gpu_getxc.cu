#include "gpu.h"
#include <cuda.h>

static __constant__ gpu_simulation_type devSim_dft;
static __constant__ QUICKDouble radii[19] = {1.e0, 0.5882e0, 3.0769e0, 
                         2.0513e0,1.5385e0, 1.2308e0, 1.0256e0,
                         0.8791e0,0.7692e0, 0.6838e0, 4.0909e0,
                         3.1579e0,2.5714e0, 2.1687e0, 1.8750e0,
                         1.6514e0,1.4754e0, 1.3333e0, 65*2.25e0};

static __constant__ QUICKDouble radii2[19] = {1.30e0,  0.0e0, 1.95e0, 2.20e0, 1.45e0, 
                            1.20e0, 1.10e0, 1.10e0, 1.20e0,  0.0e0, 
                            2.30e0, 2.20e0, 2.10e0, 1.30e0, 1.30e0, 
                            1.10e0, 1.45e0,  0.0e0, 65*2.25e0};

static __constant__ QUICKDouble RGRID[50] = { 0.000400000000, 0.001665972511, 0.003906250000, 
                            0.007243096424, 0.011814744802, 0.017777777778, 0.025309917355, 
                            0.034613304489, 0.045918367347, 0.059488399762, 0.075625000000, 
                            0.094674556213, 0.117036011080, 0.143170197224, 0.173611111111, 
                            0.208979591837, 0.250000000000, 0.297520661157, 0.352539062500, 
                            0.416233090531, 0.490000000000, 0.575505350773, 0.674744897959, 
                            0.790123456790, 0.924556213018, 1.081600000000, 1.265625000000, 
                            1.482041587902, 1.737603305785, 2.040816326531, 2.402500000000, 
                            2.836565096953, 3.361111111111, 4.000000000000, 4.785156250000, 
                            5.760000000000, 6.984693877551, 8.544378698225,10.562500000000,
                            13.223140495868,16.810000000000,21.777777777778,28.890625000000,
                            39.510204081633,56.250000000000,84.640000000000,138.062500000000,
                            256.000000000000,600.250000000000,2500.000000000000};

static __constant__ QUICKDouble RWT[50] = {0.000000000131, 0.000000004813, 0.000000042220, 
                            0.000000206165, 0.000000731384, 0.000002122603, 0.000005369349, 
                            0.000012296200, 0.000026125685, 0.000052373690, 0.000100263684, 
                            0.000184949922, 0.000331002868, 0.000577867516, 0.000988414167, 
                            0.001662355002, 0.002757352941, 0.004522359864, 0.007350524480, 
                            0.011863649113, 0.019047933333, 0.030473868600, 0.048655633610, 
                            0.077644380858, 0.124018587115, 0.198557753672, 0.319109916687, 
                            0.515579304527, 0.838747802817, 1.376167769422, 2.281385470312, 
                            3.828907341705, 6.520221288676,11.294117647059,19.957241602242,
                            36.097228800000,67.098458410034,128.799651727227,256.835164388021,
                            535.983391329609,1181.733250200000,2787.077579637250,7150.106995582581,
                            20425.715291126267,67236.328125000000,268905.261465599993,1427807.050415039062,
                            11883861.333333332092,225097464.046875000000,31875000000.000000000000};
                            

static __constant__ QUICKDouble hpartpara[4] = {0.2500e0,0.5000e0,1.0000e0,4.5000e0};
static __constant__ QUICKDouble lpartpara[4] = {0.1667e0,0.5000e0,0.9000e0,3.5000e0};
static __constant__ QUICKDouble npartpara[4] = {0.1000e0,0.4000e0,0.8000e0,2.5000e0};

/*
 upload gpu simulation type to constant memory
 */
void upload_sim_to_constant_dft(_gpu_type gpu){
    cudaError_t status;
    PRINTDEBUG("UPLOAD CONSTANT DFT");
    status = cudaMemcpyToSymbol("devSim_dft", &gpu->gpu_sim, sizeof(gpu_simulation_type), 0, cudaMemcpyHostToDevice);
    PRINTERROR(status, " cudaMemcpyToSymbol, dft sim copy to constants failed")
    PRINTDEBUG("FINISH UPLOAD CONSTANT DFT");
}


#ifdef DEBUG
static float totTime;
#endif

void getb3lyp(_gpu_type gpu)
{
#ifdef DEBUG
    cudaEvent_t start,end;
    cudaEventCreate(&start);
    cudaEventCreate(&end);
    cudaEventRecord(start, 0);
#endif
    
    getb3lyp_kernel<<<gpu->blocks, gpu->b3lypThreadsPerBlock>>>();
    
#ifdef DEBUG
    printf("Running getb3lyp_kernel with BLOCK = %i, THREADS PER BLOCK = %i \n", gpu->blocks, gpu->b3lypThreadsPerBlock);
    cudaEventRecord(end, 0);
    cudaEventSynchronize(end);
    float time;
    cudaEventElapsedTime(&time, start, end);
    totTime+=time;
    printf("this DFT cycle:%f ms total time:%f ms\n", time, totTime);
    cudaEventDestroy(start);
    cudaEventDestroy(end);
#endif
    
}
__global__ void getb3lyp_kernel()
{
    int total_num = 0;
    unsigned int offset = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned int totalThreads = blockDim.x * gridDim.x;
    QUICKULL currentPoint = 0;
    QUICKULL myPoint = offset;
    
    int radTotal;
    int iiangt;
    
    QUICKDouble XAng[MAX_GRID];
    QUICKDouble YAng[MAX_GRID];
    QUICKDouble ZAng[MAX_GRID];
    QUICKDouble WAng[MAX_GRID];
    
    for (int i = 0; i< devSim_dft.natom; i++) {
        if (devSim_dft.isg == 1) {
            radTotal = 50;
        }else {
            if (devSim_dft.iattype[i]<=10) {
                radTotal = 23;
            }else {
                radTotal = 26;
            }
        }
        for (int j = 0; j<radTotal; j++) {
             
            // Generates grids points according to central atom type and distance to atoms. See subroutines for details.
            if (devSim_dft.isg == 1){ // SG1 scheme
                iiangt = gridFormSG1(i+1, RGRID[j], XAng, YAng, ZAng, WAng);
            }else {                   // SG0 scheme
                // iiangt = gridFormSG0(*atm, *iradtemp+1-*irad, RGRID, RWT);
            }
            
            if (currentPoint <= myPoint && currentPoint + iiangt > myPoint) {
                unsigned int pointId = (unsigned int) myPoint - currentPoint;
                gpu_grid_b3lyp(j+1, radTotal, i+1, XAng[pointId], YAng[pointId], ZAng[pointId], WAng[pointId]);
                myPoint = myPoint + totalThreads;
            }
            currentPoint = currentPoint + iiangt;
        }
    }
    
}



/*
 This subroutine is to get energy, electron density, deviation and operator change
 if given a point in grid.
 */
__device__ void gpu_grid_b3lyp(int irad, int iradtemp, int iatm, QUICKDouble XAng, QUICKDouble YAng, QUICKDouble ZAng, QUICKDouble WAng){
    
    
    QUICKDouble rad, rad3;    
    QUICKDouble atomx, atomy, atomz;
    
    /*
     Read atom coordinates(atomx, atomy and atomz) from global memory (DRAM). If the atom is shared by the 
     whole block, we could put these variables into block memory (shared memory)
     */
    atomx = LOC2(devSim_dft.xyz, 0, iatm-1, 3, devSim_dft.natom);
    atomy = LOC2(devSim_dft.xyz, 1, iatm-1, 3, devSim_dft.natom);
    atomz = LOC2(devSim_dft.xyz, 2, iatm-1, 3, devSim_dft.natom);
    
    if (devSim_dft.isg == 1){
        rad = radii[devSim_dft.iattype[iatm-1]-1];
        rad3 = pow(rad,3) * RWT[irad-1];
        
    }else {
        rad = radii2[devSim_dft.iattype[iatm-1]-1];
        rad3 = pow(rad,3) * RWT[irad-1];
    }
    
    // grid point coordinates.
    QUICKDouble gridx = atomx + rad * RGRID[irad-1] * XAng;
    QUICKDouble gridy = atomy + rad * RGRID[irad-1] * YAng;
    QUICKDouble gridz = atomz + rad * RGRID[irad-1] * ZAng;
    
    // calculate Scuseria-Stratmann weights, and times rad3 and the point basic weights to get comprhensive point weight
    QUICKDouble weight = SSW(gridx, gridy, gridz, iatm) * WAng * rad3;
    
    if (weight > devSim_dft.DMCutoff ) { //!!!! remember to change gpu -> gpu_cutoff -> integralCutoff * 0.1 to DMCutoff!!!!
        
        QUICKDouble density, densityb;
        QUICKDouble gax, gay, gaz;
        QUICKDouble gbx, gby, gbz;
        denspt(gridx, gridy, gridz, &density, &densityb, &gax, &gay, &gaz, &gbx, &gby, &gbz);
        
        if (density > devSim_dft.DMCutoff ) { //!!!! remember to change gpu -> gpu_cutoff -> integralCutoff * 0.1 to DMCutoff!!!!
            QUICKDouble sigma = 4.0 * (gax * gax + gay * gay + gaz * gaz);
            
            QUICKDouble _tmp = b3lyp_e(2.0*density, sigma) * weight;
            
            QUICKULL val1 = (QUICKULL) (fabs( _tmp * OSCALE) + (QUICKDouble)0.5);
            if ( _tmp * weight < (QUICKDouble)0.0)
                val1 = 0ull - val1;                               
            QUICKADD(devSim_dft.DFT_calculated[0].Eelxc, val1);

            _tmp = weight*density;
            val1 = (QUICKULL) (fabs( _tmp * OSCALE) + (QUICKDouble)0.5);
            if ( _tmp * weight < (QUICKDouble)0.0)
                val1 = 0ull - val1;                               
            QUICKADD(devSim_dft.DFT_calculated[0].aelec, val1);
            
            
            _tmp = weight*densityb;
            val1 = (QUICKULL) (fabs( _tmp * OSCALE) + (QUICKDouble)0.5);
            if ( _tmp * weight < (QUICKDouble)0.0)
                val1 = 0ull - val1;                               
            QUICKADD(devSim_dft.DFT_calculated[0].belec, val1);
            
            QUICKDouble dfdr;
            QUICKDouble dot = b3lypf(2.0*density, sigma, &dfdr);
            QUICKDouble xdot = dot * gax;
            QUICKDouble ydot = dot * gay;
            QUICKDouble zdot = dot * gaz;
            for (int i = 0; i< devSim_dft.nbasis; i++) {
                QUICKDouble phi, dphidx, dphidy, dphidz;
                pteval(gridx, gridy, gridz, &phi, &dphidx, &dphidy, &dphidz, i+1);
                
                if (abs(phi+dphidx+dphidy+dphidz)> devSim_dft.DMCutoff ) { //!!!! remember to change gpu -> gpu_cutoff -> integralCutoff * 0.1 to DMCutoff!!!!
                    for (int j = i; j<devSim_dft.nbasis; j++) {
                        QUICKDouble phi2, dphidx2, dphidy2, dphidz2;
                        pteval(gridx, gridy, gridz, &phi2, &dphidx2, &dphidy2, &dphidz2, j+1);
                        
                        QUICKDouble _tmp = (phi * phi2 * dfdr + xdot * (phi*dphidx2 + phi2*dphidx) \
                                            + ydot * (phi*dphidy2 + phi2*dphidy) + zdot * (phi*dphidz2 + phi2*dphidz))*weight;
                        
                        QUICKULL val1 = (QUICKULL) (fabs( _tmp * OSCALE) + (QUICKDouble)0.5);
                        if ( _tmp * weight < (QUICKDouble)0.0)
                            val1 = 0ull - val1;                               
                        QUICKADD(LOC2(devSim_dft.oULL, j, i, devSim_dft.nbasis, devSim_dft.nbasis), val1);
                        
                    }
                }
            }
        }
    }
}


__device__ int gridFormSG1(int iitype, QUICKDouble distance, \
    QUICKDouble* XAng, QUICKDouble* YAng, QUICKDouble* ZAng, QUICKDouble* WAng){
    int iiang;
    int N = 0;
    
    if (devSim_dft.iattype[iitype-1] >= 1 && devSim_dft.iattype[iitype-1] <=2) {
    
        if (distance<hpartpara[0]) {
            LD0006(XAng, YAng, ZAng, WAng, N);
            iiang = 6;
        }else if (distance<hpartpara[1]) {
            LD0038(XAng, YAng, ZAng, WAng, N);
            iiang = 38;
        }else if (distance<hpartpara[2]) {
            LD0086(XAng, YAng, ZAng, WAng, N);
            iiang = 86;
        }else if (distance<hpartpara[3]) {
            LD0194(XAng, YAng, ZAng, WAng, N);
            iiang = 194;
        }else{
            LD0086(XAng, YAng, ZAng, WAng, N);
            iiang = 86;
        }
    }else if (devSim_dft.iattype[iitype-1] >= 3 && devSim_dft.iattype[iitype-1] <=10) {
        if (distance<lpartpara[0]) {
            LD0006(XAng, YAng, ZAng, WAng, N);
            iiang = 6;
        }else if (distance<lpartpara[1]) {
            LD0038(XAng, YAng, ZAng, WAng, N);
            iiang = 38;
        }else if (distance<lpartpara[2]) {
            LD0086(XAng, YAng, ZAng, WAng, N);
            iiang = 86;
        }else if (distance<lpartpara[3]) {
            LD0194(XAng, YAng, ZAng, WAng, N);
            iiang = 194;
        }else{
            LD0086(XAng, YAng, ZAng, WAng, N);
            iiang = 86;
        }
    }else if (devSim_dft.iattype[iitype-1]>= 11 && devSim_dft.iattype[iitype-1]<=18) {
        if (distance<npartpara[0]) {
            LD0006(XAng, YAng, ZAng, WAng, N);
            iiang = 6;
        }else if (distance<npartpara[1]) {
            LD0038(XAng, YAng, ZAng, WAng, N);
            iiang = 38;
        }else if (distance<npartpara[2]) {
            LD0086(XAng, YAng, ZAng, WAng, N);
            iiang = 86;
        }else if (distance<npartpara[3]) {
            LD0194(XAng, YAng, ZAng, WAng, N);
            iiang = 194;
        }else{
            LD0086(XAng, YAng, ZAng, WAng, N);
            iiang = 86;
        }
    } else {
        LD0194(XAng, YAng, ZAng, WAng, N);
        iiang = 194;
    }
    for (int i = 0; i<iiang; i++) {
        WAng[i] = WAng[i] * 12.56637061435917295385;
    }
    return iiang;
}

__device__ QUICKDouble SSW( QUICKDouble gridx, QUICKDouble gridy, QUICKDouble gridz, int atm)
{
    
    /*
     This subroutie calculates the Scuseria-Stratmann wieghts.  There are
     two conditions that cause the weights to be unity: If there is only
     one atom:
    */
    QUICKDouble ssw;
    if (devSim_dft.natom == 1) {
        ssw = 1.0e0;
        return ssw;
    }
    
    /*
     Another time the weight is unity is r(iparent,g)<.5*(1-a)*R(i,n)
     where r(iparent,g) is the distance from the parent atom to the grid
     point, a is a parameter (=.64) and R(i,n) is the distance from the
     parent atom to it's nearest neighbor.
    */
    
    QUICKDouble xparent = LOC2(devSim_dft.xyz, 0, atm-1, 3, devSim_dft.natom);
    QUICKDouble yparent = LOC2(devSim_dft.xyz, 1, atm-1, 3, devSim_dft.natom);
    QUICKDouble zparent = LOC2(devSim_dft.xyz, 2, atm-1, 3, devSim_dft.natom);
    
    QUICKDouble rig = sqrt(pow((gridx-xparent),2) + 
                           pow((gridy-yparent),2) + 
                           pow((gridz-zparent),2)); 

    /* !!!! this part can be done in CPU*/
    QUICKDouble distnbor = 1e3;
    for (int i = 0; i<devSim_dft.natom; i++) {
        if (i != atm-1) {        
            QUICKDouble distance = sqrt(pow(xparent - LOC2(devSim_dft.xyz, 0, i, 3, devSim_dft.natom),2) + 
                                    pow(yparent - LOC2(devSim_dft.xyz, 1, i, 3, devSim_dft.natom),2) +
                                    pow(zparent - LOC2(devSim_dft.xyz, 2, i, 3, devSim_dft.natom),2));
            distnbor = (distnbor<distance)? distnbor: distance;
        }
    }   
    
    if (rig < 0.18 * distnbor) {
        ssw = 1.0e0;
        return ssw;
    }
    
    /*
     If neither of those are the case, we have to actually calculate the
     weight.  First we must calculate the unnormalized wieght of the grid point
     with respect to the parent atom.
    
     Step one of calculating the unnormalized weight is finding the confocal
     elliptical coordinate between each cell.  This it the mu with subscripted
     i and j in the paper:
     Stratmann, Scuseria, and Frisch, Chem. Phys. Lett., v 257,
     1996, pg 213-223.
     */
    QUICKDouble wofparent = 1.0e0; // weight of parents
    
    //!!! this part should be rewrite
    int jatm = 1;
    while (jatm != atm && wofparent != 0.0e0) {
        QUICKDouble xjatm = LOC2(devSim_dft.xyz, 0, jatm-1, 3, devSim_dft.natom) ;
        QUICKDouble yjatm = LOC2(devSim_dft.xyz, 1, jatm-1, 3, devSim_dft.natom) ;
        QUICKDouble zjatm = LOC2(devSim_dft.xyz, 2, jatm-1, 3, devSim_dft.natom) ;
        
        QUICKDouble rjg = sqrt(pow((gridx-xjatm),2) + pow((gridy-yjatm),2) + pow((gridz-zjatm),2)); 
        QUICKDouble rij = sqrt(pow((xparent-xjatm),2) + pow((yparent-yjatm),2) + pow((zparent-zjatm),2)); 
        QUICKDouble confocal = (rig - rjg)/rij;
     
        if (confocal >= 0.64) {
            wofparent = 0.0e0;
        }else if (confocal>=-0.64e0) {
            QUICKDouble frctn = confocal/0.64;
            QUICKDouble gofconfocal = (35.0*frctn-35.0*pow(frctn,3)+21.0*pow(frctn,5)-5.0*pow(frctn,7))/16.0;
            wofparent = wofparent*0.5*(1.0-gofconfocal);
        }
        jatm++;
    }
    
    jatm = atm+1;
    
    
    while (jatm <= devSim_dft.natom && wofparent != 0.0e0) {
        QUICKDouble xjatm = LOC2(devSim_dft.xyz, 0, jatm-1, 3, devSim_dft.natom) ;
        QUICKDouble yjatm = LOC2(devSim_dft.xyz, 1, jatm-1, 3, devSim_dft.natom) ;
        QUICKDouble zjatm = LOC2(devSim_dft.xyz, 2, jatm-1, 3, devSim_dft.natom) ;
        
        QUICKDouble rjg = sqrt(pow((gridx-xjatm),2) + pow((gridy-yjatm),2) + pow((gridz-zjatm),2)); 
        QUICKDouble rij = sqrt(pow((xparent-xjatm),2) + pow((yparent-yjatm),2) + pow((zparent-zjatm),2)); 
        QUICKDouble confocal = (rig - rjg)/rij;
        if (confocal >= 0.64) {
            wofparent = 0.0e0;
        }else if (confocal>=-0.64e0) {
            QUICKDouble frctn = confocal/0.64;
            QUICKDouble gofconfocal = (35.0*frctn-35.0*pow(frctn,3)+21.0*pow(frctn,5)-5.0*pow(frctn,7))/16.0;
            wofparent = wofparent*0.5*(1.0-gofconfocal);
        }
        jatm++;
    }
    
    
    QUICKDouble totalw = wofparent;
    if (wofparent == 0.0e0) {
        ssw = 0.0e0;
        return ssw;
    }
    
    /*    
     Now we have the unnormalized weight of the grid point with regard to the
     parent atom.  Now we have to do this for all other atom pairs to
     normalize the grid weight.
     */
    
    // !!!! this part should be rewrite
    for (int i = 0; i<devSim_dft.natom; i++) {
        if (i!=atm-1) {
            QUICKDouble xiatm = LOC2(devSim_dft.xyz, 0, i, 3, devSim_dft.natom) ;
            QUICKDouble yiatm = LOC2(devSim_dft.xyz, 1, i, 3, devSim_dft.natom) ;
            QUICKDouble ziatm = LOC2(devSim_dft.xyz, 2, i, 3, devSim_dft.natom) ;
            
            rig = sqrt(pow((gridx-xiatm),2) + pow((gridy-yiatm),2) + pow((gridz-ziatm),2)); 
            jatm = 1;
            QUICKDouble wofiatom = 1.0;
            while (jatm != i+1 && wofiatom != 0.0e0) {
                QUICKDouble xjatm = LOC2(devSim_dft.xyz, 0, jatm-1, 3, devSim_dft.natom) ;
                QUICKDouble yjatm = LOC2(devSim_dft.xyz, 1, jatm-1, 3, devSim_dft.natom) ;
                QUICKDouble zjatm = LOC2(devSim_dft.xyz, 2, jatm-1, 3, devSim_dft.natom) ;
                
                QUICKDouble rjg = sqrt(pow((gridx-xjatm),2) + pow((gridy-yjatm),2) + pow((gridz-zjatm),2)); 
                QUICKDouble rij = sqrt(pow((xiatm-xjatm),2) + pow((yiatm-yjatm),2) + pow((ziatm-zjatm),2)); 
                QUICKDouble confocal = (rig - rjg)/rij;
                if (confocal >= 0.64) {
                    wofiatom = 0.0e0;
                }else if (confocal>=-0.64e0) {
                    QUICKDouble frctn = confocal/0.64;
                    QUICKDouble gofconfocal = (35.0*frctn-35.0*pow(frctn,3)+21.0*pow(frctn,5)-5.0*pow(frctn,7))/16.0;
                    wofiatom = wofiatom*0.5*(1.0-gofconfocal);
                }
                jatm++;
            }
            
            jatm = i+2;
            while (jatm <= devSim_dft.natom && wofiatom != 0.0e0) {
                QUICKDouble xjatm = LOC2(devSim_dft.xyz, 0, jatm-1, 3, devSim_dft.natom) ;
                QUICKDouble yjatm = LOC2(devSim_dft.xyz, 1, jatm-1, 3, devSim_dft.natom) ;
                QUICKDouble zjatm = LOC2(devSim_dft.xyz, 2, jatm-1, 3, devSim_dft.natom) ;
                
                QUICKDouble rjg = sqrt(pow((gridx-xjatm),2) + pow((gridy-yjatm),2) + pow((gridz-zjatm),2)); 
                QUICKDouble rij = sqrt(pow((xiatm-xjatm),2) + pow((yiatm-yjatm),2) + pow((ziatm-zjatm),2)); 
                QUICKDouble confocal = (rig - rjg)/rij;
                
                if (confocal >= 0.64) {
                    wofiatom = 0.0e0;
                }else if (confocal>=-0.64e0) {
                    QUICKDouble frctn = confocal/0.64;
                    QUICKDouble gofconfocal = (35.0*frctn-35.0*pow(frctn,3)+21.0*pow(frctn,5)-5.0*pow(frctn,7))/16.0;
                    wofiatom = wofiatom*0.5*(1.0-gofconfocal);
                }
                jatm++;
            }
            totalw = totalw + wofiatom;
        }
    }
    ssw = wofparent/totalw;
    return ssw;
}

__device__ void pteval(QUICKDouble gridx, QUICKDouble gridy, QUICKDouble gridz, 
            QUICKDouble* phi, QUICKDouble* dphidx, QUICKDouble* dphidy,  QUICKDouble* dphidz, 
            int ibas)
{
    
    /*
      Given a point in space, this function calculates the value of basis
      function I and the value of its cartesian derivatives in all three
      derivatives.
     */
    
    // relative coordinates between grid point and basis function I.
    QUICKDouble x1 = gridx - LOC2(devSim_dft.xyz, 0, devSim_dft.ncenter[ibas-1]-1, 3, devSim_dft.natom);
    QUICKDouble y1 = gridy - LOC2(devSim_dft.xyz, 1, devSim_dft.ncenter[ibas-1]-1, 3, devSim_dft.natom);
    QUICKDouble z1 = gridz - LOC2(devSim_dft.xyz, 2, devSim_dft.ncenter[ibas-1]-1, 3, devSim_dft.natom);
    
    
    QUICKDouble x1i, y1i, z1i;
    QUICKDouble x1imin1, y1imin1, z1imin1;
    QUICKDouble x1iplus1, y1iplus1, z1iplus1;
    
    *phi = 0.0;
    *dphidx = 0.0;
    *dphidy = 0.0;
    *dphidz = 0.0;
    
    int itypex = LOC2(devSim_dft.itype, 0, ibas-1, 3, devSim_dft.nbasis);
    int itypey = LOC2(devSim_dft.itype, 1, ibas-1, 3, devSim_dft.nbasis);
    int itypez = LOC2(devSim_dft.itype, 2, ibas-1, 3, devSim_dft.nbasis);
    
    QUICKDouble dist = x1*x1+y1*y1+z1*z1;
    
    if ( dist <= devSim_dft.sigrad2[ibas-1]){
        if ( itypex == 0) {
            x1imin1 = 0.0;
            x1i = 1.0;
            x1iplus1 = x1;
        }else {
            x1imin1 = pow(x1, itypex-1);
            x1i = x1imin1 * x1;
            x1iplus1 = x1i * x1;
        }
        
        if ( itypey == 0) {
            y1imin1 = 0.0;
            y1i = 1.0;
            y1iplus1 = y1;
        }else {
            y1imin1 = pow(y1, itypey-1);
            y1i = y1imin1 * y1;
            y1iplus1 = y1i * y1;
        }
        
        if ( itypez == 0) {
            z1imin1 = 0.0;
            z1i = 1.0;
            z1iplus1 = z1;
        }else {
            z1imin1 = pow(z1, itypez-1);
            z1i = z1imin1 * z1;
            z1iplus1 = z1i * z1;
        }
        
        
        for (int i = 0; i < devSim_dft.ncontract[ibas-1]; i++) {
            QUICKDouble tmp = LOC2(devSim_dft.dcoeff, i, ibas-1, devSim_dft.maxcontract, devSim_dft.nbasis) * 
                              exp( - LOC2(devSim_dft.aexp, i, ibas-1, devSim_dft.maxcontract, devSim_dft.nbasis) * dist);
            *phi = *phi + tmp;
            *dphidx = *dphidx + tmp * ( -2.0 * LOC2(devSim_dft.aexp, i, ibas-1, devSim_dft.maxcontract, devSim_dft.nbasis)* x1iplus1 + (QUICKDouble)itypex * x1imin1);
            *dphidy = *dphidy + tmp * ( -2.0 * LOC2(devSim_dft.aexp, i, ibas-1, devSim_dft.maxcontract, devSim_dft.nbasis)* y1iplus1 + (QUICKDouble)itypey * y1imin1);
            *dphidz = *dphidz + tmp * ( -2.0 * LOC2(devSim_dft.aexp, i, ibas-1, devSim_dft.maxcontract, devSim_dft.nbasis)* z1iplus1 + (QUICKDouble)itypez * z1imin1);
        }
        
        *phi = *phi * x1i * y1i * z1i;
        *dphidx = *dphidx * y1i * z1i;
        *dphidy = *dphidy * x1i * z1i;
        *dphidz = *dphidz * x1i * y1i;
    }
}


__device__ void denspt(QUICKDouble gridx, QUICKDouble gridy, QUICKDouble gridz, QUICKDouble* density, QUICKDouble* densityb, 
            QUICKDouble* gax,   QUICKDouble* gay,   QUICKDouble* gaz,   QUICKDouble* gbx,     QUICKDouble* gby,     QUICKDouble* gbz)
{
    /*
     Given a point in space, this function calculates the densities and
     gradient  at that point.  The gradients are stored in the common block
     three element arrays ga and gb for alpha and beta electron gradients. Thus
     the x, y, z component of the alpha density is stored in gax, gay, gaz.
     */
    *density = 0.0;
    *gax = 0.0;
    *gay = 0.0;
    *gaz = 0.0;
    
    for (int i = 0; i<devSim_dft.nbasis; i++) {
        if (abs(LOC2(devSim_dft.dense, i, i, devSim_dft.nbasis, devSim_dft.nbasis)) >= devSim_dft.DMCutoff ) { //!!!! remember to change gpu -> gpu_cutoff -> integralCutoff * 0.1 to DMCutoff!!!!
            QUICKDouble phi, dphidx, dphidy, dphidz;
            pteval(gridx, gridy, gridz, &phi, &dphidx, &dphidy, &dphidz, i+1);
            
            if (abs(phi+dphidx+dphidy+dphidz) >= devSim_dft.DMCutoff ) { //!!!! remember to change gpu -> gpu_cutoff -> integralCutoff * 0.1 to DMCutoff!!!!
                QUICKDouble denseii = LOC2(devSim_dft.dense, i, i, devSim_dft.nbasis, devSim_dft.nbasis) * phi;
                *density = *density + denseii * phi / 2.0;
                *gax = *gax + denseii * dphidx;
                *gay = *gay + denseii * dphidy;
                *gaz = *gaz + denseii * dphidz;
                for (int j = i + 1; j< devSim_dft.nbasis; j++) {
                    QUICKDouble phi2, dphidx2, dphidy2, dphidz2;
                    pteval(gridx, gridy, gridz, &phi2, &dphidx2, &dphidy2, &dphidz2, j+1);
                    
                    QUICKDouble denseij = LOC2(devSim_dft.dense, i, j, devSim_dft.nbasis, devSim_dft.nbasis);
                    *density = *density + denseij * phi * phi2;
                    *gax = *gax + denseij * ( phi * dphidx2 + phi2 * dphidx );
                    *gay = *gay + denseij * ( phi * dphidy2 + phi2 * dphidy );
                    *gaz = *gaz + denseij * ( phi * dphidz2 + phi2 * dphidz );
                    
                }
            }
        }
    }
    *densityb = *density;
    *gbx = *gax;
    *gby = *gay;
    *gbz = *gaz;
}

__device__ QUICKDouble b3lyp_e(QUICKDouble rho, QUICKDouble sigma)
{
  /*
  P.J. Stephens, F.J. Devlin, C.F. Chabalowski, M.J. Frisch
  Ab initio calculation of vibrational absorption and circular
  dichroism spectra using density functional force fields
  J. Phys. Chem. 98 (1994) 11623-11627
  
  CITATION:
  Functionals were obtained from the Density Functional Repository
  as developed and distributed by the Quantum Chemistry Group,
  CCLRC Daresbury Laboratory, Daresbury, Cheshire, WA4 4AD
  United Kingdom. Contact Huub van Dam (h.j.j.vandam@dl.ac.uk) or
  Paul Sherwood for further information.
  
  COPYRIGHT:
  
  Users may incorporate the source code into software packages and
  redistribute the source code provided the source code is not
  changed in anyway and is properly cited in any documentation or
  publication related to its use.
  
  ACKNOWLEDGEMENT:
  
  The source code was generated using Maple 8 through a modified
  version of the dfauto script published in:
  
  R. Strange, F.R. Manby, P.J. Knowles
  Automatic code generation in density functional theory
  Comp. Phys. Comm. 136 (2001) 310-318.
  
  */
    QUICKDouble Eelxc = 0.0e0;
    QUICKDouble t2 = pow(rho, (1.e0/3.e0));
    QUICKDouble t3 = t2*rho;
    QUICKDouble t5 = 1/t3;
    QUICKDouble t7 = sqrt(sigma);
    QUICKDouble t8 = t7*t5;
    QUICKDouble t10 = log(0.1259921049894873e1*t8+sqrt(1+0.1587401051968199e1*t8*t8));
    QUICKDouble t17 = 1/t2;
    QUICKDouble t20 = 1/(1.e0+0.349e0*t17);
    QUICKDouble t23 = 0.2533*t17;
    QUICKDouble t24 = exp(-t23);
    QUICKDouble t26 = rho*rho;
    QUICKDouble t28 = t2*t2;
    QUICKDouble t34 = t17*t20;
    QUICKDouble t56 = 1/rho;
    QUICKDouble t57 = pow(t56,(1.e0/3.e0));
    QUICKDouble t59 = pow(t56,(1.e0/6.e0));
    QUICKDouble t62 = 1/(0.6203504908994*t57+0.1029581201158544e2*t59+0.427198e2);
    QUICKDouble t65 = log(0.6203504908994*t57*t62);
    QUICKDouble t71 = atan(0.448998886412873e-1/(0.1575246635799487e1*t59+0.13072e2));
    QUICKDouble t75 = pow((0.7876233178997433e0*t59+0.409286e0),2);
    QUICKDouble t77 = log(t75*t62);
    Eelxc = -0.5908470131056179e0*t3
            -0.3810001254882096e-2*t5*sigma/(1.e0+0.317500104573508e-1*t8*t10)
            -0.398358e-1*t20*rho 
            -0.52583256e-2*t24*t20/t28/t26/rho*(0.25e0*t26*(0.1148493600075277e2*t28*t26+(0.2611111111111111e1-0.9850555555555556e-1*t17-
    0.1357222222222222e0*t34)*sigma-0.5*(0.25e1-0.1407222222222222e-1*t17-0.1938888888888889e-1*t34)*sigma-
    0.2777777777777778e-1*(t23+0.349*t34-11.0)*sigma)-0.4583333333333333e0*t26*sigma)+
    0.19*rho*(0.310907e-1*t65+0.205219729378375e2*t71+0.4431373767749538e-2*t77);
    return Eelxc;
}
            
__device__ QUICKDouble b3lypf(QUICKDouble rho, QUICKDouble sigma, QUICKDouble* dfdr)
{
    /*
     P.J. Stephens, F.J. Devlin, C.F. Chabalowski, M.J. Frisch
     Ab initio calculation of vibrational absorption and circular
     dichroism spectra using density functional force fields
     J. Phys. Chem. 98 (1994) 11623-11627
     
     CITATION:
     Functionals were obtained from the Density Functional Repository
     as developed and distributed by the Quantum Chemistry Group,
     CCLRC Daresbury Laboratory, Daresbury, Cheshire, WA4 4AD
     United Kingdom. Contact Huub van Dam (h.j.j.vandam@dl.ac.uk) or
     Paul Sherwood for further information.
     
     COPYRIGHT:
     
     Users may incorporate the source code into software packages and
     redistribute the source code provided the source code is not
     changed in anyway and is properly cited in any documentation or
     publication related to its use.
     
     ACKNOWLEDGEMENT:
     
     The source code was generated using Maple 8 through a modified
     version of the dfauto script published in:
     
     R. Strange, F.R. Manby, P.J. Knowles
     Automatic code generation in density functional theory
     Comp. Phys. Comm. 136 (2001) 310-318.
     
     */
    QUICKDouble dot;
    QUICKDouble t2 = pow(rho, (1.e0/3.e0));
    QUICKDouble t3 = t2*rho;
    QUICKDouble t5 = 1/t3;
    QUICKDouble t6 = t5*sigma;
    QUICKDouble t7 = sqrt(sigma);
    QUICKDouble t8 = t7*t5;
    QUICKDouble t10 = log(0.1259921049894873e1*t8+sqrt(1+0.1587401051968199e1*t8*t8));
    QUICKDouble t13 = 1.0e0+0.317500104573508e-1*t8*t10;
    QUICKDouble t14 = 1.0e0/t13;
    QUICKDouble t17 = 1/t2;
    QUICKDouble t19 = 1.e0+0.349e0*t17;
    QUICKDouble t20 = 1/t19;
    QUICKDouble t23 = 0.2533e0*t17;
    QUICKDouble t24 = exp(-t23);
    QUICKDouble t25 = t24*t20;
    QUICKDouble t26 = rho*rho;
    QUICKDouble t28 = t2*t2;
    QUICKDouble t30 = 1/t28/t26/rho;
    QUICKDouble t31 = t28*t26;
    QUICKDouble t34 = t17*t20;
    
    QUICKDouble t36 = 0.2611111111111111e1-0.9850555555555556e-1*t17-0.1357222222222222e0*t34;
    QUICKDouble t44 = t23+0.349e0*t34-11.e0;
    QUICKDouble t47 = 0.1148493600075277e2*t31+t36*sigma-0.5e0*(0.25e1-0.1407222222222222e-1*t17- \
                      0.1938888888888889e-1*t34)*sigma-0.2777777777777778e-1*t44*sigma;
    
    QUICKDouble t52 = 0.25e0*t26*t47-0.4583333333333333e0*t26*sigma;
    QUICKDouble t56 = 1/rho;
    QUICKDouble t57 = pow(t56,(1.e0/3.e0));
    QUICKDouble t59 = pow(t56,(1.e0/6.e0));
    QUICKDouble t61 = 0.6203504908994e0*t57+0.1029581201158544e2*t59+0.427198e2;
    QUICKDouble t62 = 1/t61;
    QUICKDouble t65 = log(0.6203504908994e0*t57*t62);
    QUICKDouble t68 = 0.1575246635799487e1*t59+0.13072e2;
    QUICKDouble t71 = atan(0.448998886412873e-1/t68);
    QUICKDouble t74 = 0.7876233178997433e0*t59+0.409286e0;
    QUICKDouble t75 = t74*t74;
    QUICKDouble t77 = log(t75*t62);
    QUICKDouble t84 = 1/t2/t26;
    QUICKDouble t88 = t13*t13;
    QUICKDouble t89 = 1/t88;
    QUICKDouble t94 = 1/t31;
    QUICKDouble t98 = sqrt(1.e0+0.1587401051968199e1*sigma*t94);
    QUICKDouble t99 = 1/t98;
    QUICKDouble t109 = t28*rho;
    QUICKDouble t112 = t44*t56*sigma;
    QUICKDouble t117 = rho*sigma;
    QUICKDouble t123 = t19*t19;
    QUICKDouble t124 = 1/t123;
    QUICKDouble t127 = t26*t26;
    QUICKDouble t129 = 1/t127/rho;
    QUICKDouble t144 = t5*t20;
    QUICKDouble t146 = 1/t109;
    QUICKDouble t147 = t146*t124;
    QUICKDouble t175 = t57*t57;
    QUICKDouble t176 = 1/t175;
    QUICKDouble t178 = 1/t26;
    QUICKDouble t181 = t61*t61;
    QUICKDouble t182 = 1/t181;
    QUICKDouble t186 = t59*t59;
    QUICKDouble t187 = t186*t186;
    QUICKDouble t189 = 1/t187/t59;
    QUICKDouble t190 = t189*t178;
    QUICKDouble t192 = -0.2067834969664667e0*t176*t178-0.1715968668597574e1*t190;
    QUICKDouble t200 = t68*t68;
    QUICKDouble t201 = 1/t200;
    
    *dfdr=-0.7877960174741572e0*t2+0.5080001673176129e-2*t84*sigma*t14+0.1905000627441048e-2*t6*t89*
    (-0.8466669455293548e-1*t7*t84*t10-0.106673350692263e0*sigma*t30*t99)-0.398358e-1*t20-0.52583256e-2*t25*t30*(0.5e0*rho*t47+0.25e0*t26* 
    (0.3062649600200738e2*t109-0.2777777777777778e-1*t112)-0.25e0*t117)-0.46342314e-2*t124*t17-0.44397795816e-3*t129*t24*t20*t52;
    
    *dfdr= *dfdr-0.6117185448e-3*t24*t124*t129*t52+0.192805272e-1*t25/t28/t127*t52-0.52583256e-2*t25*t30*(0.25e0*t26*((0.3283518518518519e-1*t5+0.4524074074074074e-1*t144 
    -0.1578901851851852e-1*t147)*sigma-0.5e0*(0.4690740740740741e-2*t5+0.6462962962962963e-2*t144-0.2255574074074074e-2*t147)*sigma 
    -0.2777777777777778e-1*(-0.8443333333333333e-1*t5-0.1163333333333333e0*t144+0.4060033333333333e-1*t147)*sigma+0.2777777777777778e-1*t112)-0.6666666666666667e0*t117);
    
    
    *dfdr = *dfdr+0.5907233e-2*t65+0.3899174858189126e1*t71+0.8419610158724123e-3*t77+
    0.19e0*rho*(0.5011795824473985e-1*(-0.2067834969664667e0*t176*t62*t178-0.6203504908994e0*t57*t182*t192)/t57*t61
               +0.2419143800947354e0*t201*t189*t178/(1.e0+0.2016e-2*t201)+
               0.4431373767749538e-2*(-0.2625411059665811e0*t74*t62*t190-1.e0*t75*t182*t192)/t75*t61);
    dot = -0.1524000501952839e-1*t5*t14+0.3810001254882096e-2*t6*t89*(0.6350002091470161e-1/t7*t5*t10 
        +0.8000501301919725e-1*t94*t99)+0.5842584e-3*t25*t146-0.210333024e-1*t25*t30*(0.25e0*t26*t36-0.6666666666666667e0*t26);
         
    return dot;
         
}


__device__ int gen_oh(int code, int num, QUICKDouble* x, QUICKDouble* y, QUICKDouble* z, QUICKDouble* w, QUICKDouble a, QUICKDouble b, QUICKDouble v)
{
    /*
     ! vd
     ! vd   This subroutine is part of a set of subroutines that generate
     ! vd   Lebedev grids [1-6] for integration on a sphere. The original
     ! vd   C-code [1] was kindly provided by Dr. Dmitri N. Laikov and
     ! vd   translated into fortran by Dr. Christoph van Wuellen.
     ! vd   
     ! vd   Users of this code are asked to include reference [1] in their
     ! vd   publications, and in the user- and programmers-manuals
     ! vd   describing their codes.
     ! vd
     ! vd   This code was distributed through CCL (http://www.ccl.net/).
     ! vd
     ! vd   [1] V.I. Lebedev, and D.N. Laikov
     ! vd       "A quadrature formula for the sphere of the 131st
     ! vd        algebraic order of accuracy"
     ! vd       doklady Mathematics, Vol. 59, No. 3, 1999, pp. 477-481.
     ! vd
     ! vd   [2] V.I. Lebedev
     ! vd       "A quadrature formula for the sphere of 59th algebraic
     ! vd        order of accuracy"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 50, 1995, pp. 283-286.
     ! vd
     ! vd   [3] V.I. Lebedev, and A.L. Skorokhodov
     ! vd       "Quadrature formulas of orders 41, 47, and 53 for the sphere"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 45, 1992, pp. 587-592.
     ! vd
     ! vd   [4] V.I. Lebedev
     ! vd       "Spherical quadrature formulas exact to orders 25-29"
     ! vd       Siberian Mathematical Journal, Vol. 18, 1977, pp. 99-107.
     ! vd
     ! vd   [5] V.I. Lebedev
     ! vd       "Quadratures on a sphere"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 16,
     ! vd       1976, pp. 10-24.
     ! vd
     ! vd   [6] V.I. Lebedev
     ! vd       "Values of the nodes and weights of ninth to seventeenth
     ! vd        order Gauss-Markov quadrature formulae invariant under the
     ! vd        octahedron group with inversion"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 15,
     ! vd       1975, pp. 44-51.
     ! vd
     ! w
     ! w    Given a point on a sphere (specified by a and b), generate all
     ! w    the equivalent points under Oh symmetry, making grid points with
     ! w    weight v.
     ! w    The variable num is increased by the number of different points
     ! w    generated.
     ! w
     ! w    Depending on code, there are 6...48 different but equivalent
     ! w    points.
     ! w
     ! w    code=1:   (0,0,1) etc                                (  6 points)
     ! w    code=2:   (0,a,a) etc, a=1/sqrt(2)                   ( 12 points)
     ! w    code=3:   (a,a,a) etc, a=1/sqrt(3)                   (  8 points)
     ! w    code=4:   (a,a,b) etc, b=sqrt(1-2 a^2)               ( 24 points)
     ! w    code=5:   (a,b,0) etc, b=sqrt(1-a^2), a input        ( 24 points)
     ! w    code=6:   (a,b,c) etc, c=sqrt(1-a^2-b^2), a/b input  ( 48 points)
     ! w
     */
    QUICKDouble c;
    switch (code) {
        case 1:
        {
            a=1.0e0;
            x[0+num] =  a;
            y[0+num] =  0.0e0;
            z[0+num] =  0.0e0;
            w[0+num] =  v;
            x[1+num] = -a;
            y[1+num] =  0.0e0;
            z[1+num] =  0.0e0;
            w[1+num] =  v;
            x[2+num] =  0.0e0;
            y[2+num] =  a;
            z[2+num] =  0.0e0;
            w[2+num] =  v;
            x[3+num] =  0.0e0;
            y[3+num] = -a;
            z[3+num] =  0.0e0;
            w[3+num] =  v;
            x[4+num] =  0.0e0;
            y[4+num] =  0.0e0;
            z[4+num] =  a;
            w[4+num] =  v;
            x[5+num] =  0.0e0;
            y[5+num] =  0.0e0;
            z[5+num] = -a;
            w[5+num] =  v;
            num=num+6;
            break;
        }
        case 2:
        {
            a=sqrt(0.5e0);
            x[0+num] =  0e0;
            y[0+num] =  a;
            z[0+num] =  a;
            w[0+num] =  v;
            x[1+num] =  0e0;
            y[1+num] = -a;
            z[1+num] =  a;
            w[1+num] =  v;
            x[2+num] =  0e0;
            y[2+num] =  a;
            z[2+num] = -a;
            w[2+num] =  v;
            x[3+num] =  0e0;
            y[3+num] = -a;
            z[3+num] = -a;
            w[3+num] =  v;
            x[4+num] =  a;
            y[4+num] =  0e0;
            z[4+num] =  a;
            w[4+num] =  v;
            x[5+num] = -a;
            y[5+num] =  0e0;
            z[5+num] =  a;
            w[5+num] =  v;
            x[6+num] =  a;
            y[6+num] =  0e0;
            z[6+num] = -a;
            w[6+num] =  v;
            x[7+num] = -a;
            y[7+num] =  0e0;
            z[7+num] = -a;
            w[7+num] =  v;
            x[8+num] =  a;
            y[8+num] =  a;
            z[8+num] =  0e0;
            w[8+num] =  v;
            x[9+num] = -a;
            y[9+num] =  a;
            z[9+num] =  0e0;
            w[9+num] =  v;
            x[10+num] =  a;
            y[10+num] = -a;
            z[10+num] =  0e0;
            w[10+num] =  v;
            x[11+num] = -a;
            y[11+num] = -a;
            z[11+num] =  0e0;
            w[11+num] =  v;
            num=num+12;
            break;
        }
        case 3:
        {
            a = sqrt(1e0/3e0);
            x[0+num] =  a;
            y[0+num] =  a;
            z[0+num] =  a;
            w[0+num] =  v;
            x[1+num] = -a;
            y[1+num] =  a;
            z[1+num] =  a;
            w[1+num] =  v;
            x[2+num] =  a;
            y[2+num] = -a;
            z[2+num] =  a;
            w[2+num] =  v;
            x[3+num] = -a;
            y[3+num] = -a;
            z[3+num] =  a;
            w[3+num] =  v;
            x[4+num] =  a;
            y[4+num] =  a;
            z[4+num] = -a;
            w[4+num] =  v;
            x[5+num] = -a;
            y[5+num] =  a;
            z[5+num] = -a;
            w[5+num] =  v;
            x[6+num] =  a;
            y[6+num] = -a;
            z[6+num] = -a;
            w[6+num] =  v;
            y[7+num] = -a;
            x[7+num] = -a;
            z[7+num] = -a;
            w[7+num] =  v;
            num=num+8;
            break;
        }
        case 4:
        {
            b = sqrt(1e0 - 2e0*a*a);
            x[0+num] =  a;
            y[0+num] =  a;
            z[0+num] =  b;
            w[0+num] =  v;
            x[1+num] = -a;
            y[1+num] =  a;
            z[1+num] =  b;
            w[1+num] =  v;
            x[2+num] =  a;
            y[2+num] = -a;
            z[2+num] =  b;
            w[2+num] =  v;
            x[3+num] = -a;
            y[3+num] = -a;
            z[3+num] =  b;
            w[3+num] =  v;
            x[4+num] =  a;
            y[4+num] =  a;
            z[4+num] = -b;
            w[4+num] =  v;
            x[5+num] = -a;
            y[5+num] =  a;
            z[5+num] = -b;
            w[5+num] =  v;
            x[6+num] =  a;
            y[6+num] = -a;
            z[6+num] = -b;
            w[6+num] =  v;
            x[7+num] = -a;
            y[7+num] = -a;
            z[7+num] = -b;
            w[7+num] =  v;
            x[8+num] =  a;
            y[8+num] =  b;
            z[8+num] =  a;
            w[8+num] =  v;
            x[9+num] = -a;
            y[9+num] =  b;
            z[9+num] =  a;
            w[9+num] =  v;
            x[10+num] =  a;
            y[10+num] = -b;
            z[10+num] =  a;
            w[10+num] =  v;
            x[11+num] = -a;
            y[11+num] = -b;
            z[11+num] =  a;
            w[11+num] =  v;
            x[12+num] =  a;
            y[12+num] =  b;
            z[12+num] = -a;
            w[12+num] =  v;
            x[13+num] = -a;
            y[13+num] =  b;
            z[13+num] = -a;
            w[13+num] =  v;
            x[14+num] =  a;
            y[14+num] = -b;
            z[14+num] = -a;
            w[14+num] =  v;
            x[15+num] = -a;
            y[15+num] = -b;
            z[15+num] = -a;
            w[15+num] =  v;
            x[16+num] =  b;
            y[16+num] =  a;
            z[16+num] =  a;
            w[16+num] =  v;
            x[17+num] = -b;
            y[17+num] =  a;
            z[17+num] =  a;
            w[17+num] =  v;
            x[18+num] =  b;
            y[18+num] = -a;
            z[18+num] =  a;
            w[18+num] =  v;
            x[19+num] = -b;
            y[19+num] = -a;
            z[19+num] =  a;
            w[19+num] =  v;
            x[20+num] =  b;
            y[20+num] =  a;
            z[20+num] = -a;
            w[20+num] =  v;
            x[21+num] = -b;
            y[21+num] =  a;
            z[21+num] = -a;
            w[21+num] =  v;
            x[22+num] =  b;
            y[22+num] = -a;
            z[22+num] = -a;
            w[22+num] =  v;
            x[23+num] = -b;
            y[23+num] = -a;
            z[23+num] = -a;
            w[23+num] =  v;
            num = num + 24;
            break;
        }
        case 5:
        {
            b=sqrt(1e0-a*a);
            x[0+num] =  a;
            y[0+num] =  b;
            z[0+num] =  0e0;
            w[0+num] =  v;
            x[1+num] = -a;
            y[1+num] =  b;
            z[1+num] =  0e0;
            w[1+num] =  v;
            x[2+num] =  a;
            y[2+num] = -b;
            z[2+num] =  0e0;
            w[2+num] =  v;
            x[3+num] = -a;
            y[3+num] = -b;
            z[3+num] =  0e0;
            w[3+num] =  v;
            x[4+num] =  b;
            y[4+num] =  a;
            z[4+num] =  0e0;
            w[4+num] =  v;
            x[5+num] = -b;
            y[5+num] =  a;
            z[5+num] =  0e0;
            w[5+num] =  v;
            x[6+num] =  b;
            y[6+num] = -a;
            z[6+num] =  0e0;
            w[6+num] =  v;
            x[7+num] = -b;
            y[7+num] = -a;
            z[7+num] =  0e0;
            w[7+num] =  v;
            x[8+num] =  a;
            y[8+num] =  0e0;
            z[8+num] =  b;
            w[8+num] =  v;
            x[9+num] = -a;
            y[9+num] =  0e0;
            z[9+num] =  b;
            w[9+num] =  v;
            x[10+num] =  a;
            y[10+num] =  0e0;
            z[10+num] = -b;
            w[10+num] =  v;
            x[11+num] = -a;
            y[11+num] =  0e0;
            z[11+num] = -b;
            w[11+num] =  v;
            x[12+num] =  b;
            y[12+num] =  0e0;
            z[12+num] =  a;
            w[12+num] =  v;
            x[13+num] = -b;
            y[13+num] =  0e0;
            z[13+num] =  a;
            w[13+num] =  v;
            x[14+num] =  b;
            y[14+num] =  0e0;
            z[14+num] = -a;
            w[14+num] =  v;
            x[15+num] = -b;
            y[15+num] =  0e0;
            z[15+num] = -a;
            w[15+num] =  v;
            x[16+num] =  0e0;
            y[16+num] =  a;
            z[16+num] =  b;
            w[16+num] =  v;
            x[17+num] =  0e0;
            y[17+num] = -a;
            z[17+num] =  b;
            w[17+num] =  v;
            x[18+num] =  0e0;
            y[18+num] =  a;
            z[18+num] = -b;
            w[18+num] =  v;
            x[19+num] =  0e0;
            y[19+num] = -a;
            z[19+num] = -b;
            w[19+num] =  v;
            x[20+num] =  0e0;
            y[20+num] =  b;
            z[20+num] =  a;
            w[20+num] =  v;
            x[21+num] =  0e0;
            y[21+num] = -b;
            z[21+num] =  a;
            w[21+num] =  v;
            x[22+num] =  0e0;
            y[22+num] =  b;
            z[22+num] = -a;
            w[22+num] =  v;
            x[23+num] =  0e0;
            y[23+num] = -b;
            z[23+num] = -a;
            w[23+num] =  v;
            num=num+24;
            break;
        }
        case 6:
        {
            c=sqrt(1e0 - a*a - b*b);
            x[0+num] =  a;
            y[0+num] =  b;
            z[0+num] =  c;
            w[0+num] =  v;
            x[1+num] = -a;
            y[1+num] =  b;
            z[1+num] =  c;
            w[1+num] =  v;
            x[2+num] =  a;
            y[2+num] = -b;
            z[2+num] =  c;
            w[2+num] =  v;
            x[3+num] = -a;
            y[3+num] = -b;
            z[3+num] =  c;
            w[3+num] =  v;
            x[4+num] =  a;
            y[4+num] =  b;
            z[4+num] = -c;
            w[4+num] =  v;
            x[5+num] = -a;
            y[5+num] =  b;
            z[5+num] = -c;
            w[5+num] =  v;
            x[6+num] =  a;
            y[6+num] = -b;
            z[6+num] = -c;
            w[6+num] =  v;
            x[7+num] = -a;
            y[7+num] = -b;
            z[7+num] = -c;
            w[7+num] =  v;
            x[8+num] =  a;
            y[8+num] =  c;
            z[8+num] =  b;
            w[8+num] =  v;
            x[9+num] = -a;
            y[9+num] =  c;
            z[9+num] =  b;
            w[9+num] =  v;
            x[10+num] =  a;
            y[10+num] = -c;
            z[10+num] =  b;
            w[10+num] =  v;
            x[11+num] = -a;
            y[11+num] = -c;
            z[11+num] =  b;
            w[11+num] =  v;
            x[12+num] =  a;
            y[12+num] =  c;
            z[12+num] = -b;
            w[12+num] =  v;
            x[13+num] = -a;
            y[13+num] =  c;
            z[13+num] = -b;
            w[13+num] =  v;
            x[14+num] =  a;
            y[14+num] = -c;
            z[14+num] = -b;
            w[14+num] =  v;
            x[15+num] = -a;
            y[15+num] = -c;
            z[15+num] = -b;
            w[15+num] =  v;
            x[16+num] =  b;
            y[16+num] =  a;
            z[16+num] =  c;
            w[16+num] =  v;
            x[17+num] = -b;
            y[17+num] =  a;
            z[17+num] =  c;
            w[17+num] =  v;
            x[18+num] =  b;
            y[18+num] = -a;
            z[18+num] =  c;
            w[18+num] =  v;
            x[19+num] = -b;
            y[19+num] = -a;
            z[19+num] =  c;
            w[19+num] =  v;
            x[20+num] =  b;
            y[20+num] =  a;
            z[20+num] = -c;
            w[20+num] =  v;
            x[21+num] = -b;
            y[21+num] =  a;
            z[21+num] = -c;
            w[21+num] =  v;
            x[22+num] =  b;
            y[22+num] = -a;
            z[22+num] = -c;
            w[22+num] =  v;
            x[23+num] = -b;
            y[23+num] = -a;
            z[23+num] = -c;
            w[23+num] =  v;
            x[24+num] =  b;
            y[24+num] =  c;
            z[24+num] =  a;
            w[24+num] =  v;
            x[25+num] = -b;
            y[25+num] =  c;
            z[25+num] =  a;
            w[25+num] =  v;
            x[26+num] =  b;
            y[26+num] = -c;
            z[26+num] =  a;
            w[26+num] =  v;
            x[27+num] = -b;
            y[27+num] = -c;
            z[27+num] =  a;
            w[27+num] =  v;
            x[28+num] =  b;
            y[28+num] =  c;
            z[28+num] = -a;
            w[28+num] =  v;
            x[29+num] = -b;
            y[29+num] =  c;
            z[29+num] = -a;
            w[29+num] =  v;
            x[30+num] =  b;
            y[30+num] = -c;
            z[30+num] = -a;
            w[30+num] =  v;
            x[31+num] = -b;
            y[31+num] = -c;
            z[31+num] = -a;
            w[31+num] =  v;
            x[32+num] =  c;
            y[32+num] =  a;
            z[32+num] =  b;
            w[32+num] =  v;
            x[33+num] = -c;
            y[33+num] =  a;
            z[33+num] =  b;
            w[33+num] =  v;
            x[34+num] =  c;
            y[34+num] = -a;
            z[34+num] =  b;
            w[34+num] =  v;
            x[35+num] = -c;
            y[35+num] = -a;
            z[35+num] =  b;
            w[35+num] =  v;
            x[36+num] =  c;
            y[36+num] =  a;
            z[36+num] = -b;
            w[36+num] =  v;
            x[37+num] = -c;
            y[37+num] =  a;
            z[37+num] = -b;
            w[37+num] =  v;
            x[38+num] =  c;
            y[38+num] = -a;
            z[38+num] = -b;
            w[38+num] =  v;
            x[39+num] = -c;
            y[39+num] = -a;
            z[39+num] = -b;
            w[39+num] =  v;
            x[40+num] =  c;
            y[40+num] =  b;
            z[40+num] =  a;
            w[40+num] =  v;
            x[41+num] = -c;
            y[41+num] =  b;
            z[41+num] =  a;
            w[41+num] =  v;
            x[42+num] =  c;
            y[42+num] = -b;
            z[42+num] =  a;
            w[42+num] =  v;
            x[43+num] = -c;
            y[43+num] = -b;
            z[43+num] =  a;
            w[43+num] =  v;
            x[44+num] =  c;
            y[44+num] =  b;
            z[44+num] = -a;
            w[44+num] =  v;
            x[45+num] = -c;
            y[45+num] =  b;
            z[45+num] = -a;
            w[45+num] =  v;
            x[46+num] =  c;
            y[46+num] = -b;
            z[46+num] = -a;
            w[46+num] =  v;
            x[47+num] = -c;
            y[47+num] = -b;
            z[47+num] = -a;
            w[47+num] =  v;
            num=num+48;
            break;
        default:
            break;
        }
    }
    return num;
}


__device__ void LD0006(QUICKDouble* x, QUICKDouble* y, QUICKDouble* z, QUICKDouble* w, int N)
{
    /*
     ! W
     ! W    LEBEDEV    6-POINT ANGULAR GRID
     ! W
     ! vd
     ! vd   This subroutine is part of a set of subroutines that generate
     ! vd   Lebedev grids [1-6] for integration on a sphere. The original
     ! vd   C-code [1] was kindly provided by Dr. Dmitri N. Laikov and
     ! vd   translated into fortran by Dr. Christoph van Wuellen.
     ! vd   
     ! vd
     ! vd   Users of this code are asked to include reference [1] in their
     ! vd   publications, and in the user- and programmers-manuals
     ! vd   describing their codes.
     ! vd
     ! vd   This code was distributed through CCL (http://www.ccl.net/).
     ! vd
     ! vd   [1] V.I. Lebedev, and D.N. Laikov
     ! vd       "A quadrature formula for the sphere of the 131st
     ! vd        algebraic order of accuracy"
     ! vd       doklady Mathematics, Vol. 59, No. 3, 1999, pp. 477-481.
     ! vd
     ! vd   [2] V.I. Lebedev
     ! vd       "A quadrature formula for the sphere of 59th algebraic
     ! vd        order of accuracy"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 50, 1995, pp. 283-286.
     ! vd
     ! vd   [3] V.I. Lebedev, and A.L. Skorokhodov
     ! vd       "Quadrature formulas of orders 41, 47, and 53 for the sphere"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 45, 1992, pp. 587-592.
     ! vd
     ! vd   [4] V.I. Lebedev
     ! vd       "Spherical quadrature formulas exact to orders 25-29"
     ! vd       Siberian Mathematical Journal, Vol. 18, 1977, pp. 99-107.
     ! vd
     ! vd   [5] V.I. Lebedev
     ! vd       "Quadratures on a sphere"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 16,
     ! vd       1976, pp. 10-24.
     ! vd
     ! vd   [6] V.I. Lebedev
     ! vd       "Values of the nodes and weights of ninth to seventeenth
     ! vd        order Gauss-Markov quadrature formulae invariant under the
     ! vd        octahedron group with inversion"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 15,
     ! vd       1975, pp. 44-51.
     ! vd
     */
    N = 0;
    QUICKDouble a = 0;
    QUICKDouble b = 0;
    QUICKDouble v = 0.1666666666666667;
    N = gen_oh( 1, N, x, y, z, w, a, b, v);
    N = N-1;
}

__device__ void LD0014(QUICKDouble* x, QUICKDouble* y, QUICKDouble* z, QUICKDouble* w, int N)
{
    /*
     ! W
     ! W    LEBEDEV    14-POINT ANGULAR GRID
     ! W
     ! vd
     ! vd   This subroutine is part of a set of subroutines that generate
     ! vd   Lebedev grids [1-6] for integration on a sphere. The original
     ! vd   C-code [1] was kindly provided by Dr. Dmitri N. Laikov and
     ! vd   translated into fortran by Dr. Christoph van Wuellen.
     ! vd   
     ! vd
     ! vd   Users of this code are asked to include reference [1] in their
     ! vd   publications, and in the user- and programmers-manuals
     ! vd   describing their codes.
     ! vd
     ! vd   This code was distributed through CCL (http://www.ccl.net/).
     ! vd
     ! vd   [1] V.I. Lebedev, and D.N. Laikov
     ! vd       "A quadrature formula for the sphere of the 131st
     ! vd        algebraic order of accuracy"
     ! vd       doklady Mathematics, Vol. 59, No. 3, 1999, pp. 477-481.
     ! vd
     ! vd   [2] V.I. Lebedev
     ! vd       "A quadrature formula for the sphere of 59th algebraic
     ! vd        order of accuracy"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 50, 1995, pp. 283-286.
     ! vd
     ! vd   [3] V.I. Lebedev, and A.L. Skorokhodov
     ! vd       "Quadrature formulas of orders 41, 47, and 53 for the sphere"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 45, 1992, pp. 587-592.
     ! vd
     ! vd   [4] V.I. Lebedev
     ! vd       "Spherical quadrature formulas exact to orders 25-29"
     ! vd       Siberian Mathematical Journal, Vol. 18, 1977, pp. 99-107.
     ! vd
     ! vd   [5] V.I. Lebedev
     ! vd       "Quadratures on a sphere"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 16,
     ! vd       1976, pp. 10-24.
     ! vd
     ! vd   [6] V.I. Lebedev
     ! vd       "Values of the nodes and weights of ninth to seventeenth
     ! vd        order Gauss-Markov quadrature formulae invariant under the
     ! vd        octahedron group with inversion"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 15,
     ! vd       1975, pp. 44-51.
     ! vd
     */
    N = 0;
    QUICKDouble a = 0;
    QUICKDouble b = 0;
    QUICKDouble v = 0.6666666666666667e-1;
    N = gen_oh( 1, N, x, y, z, w, a, b, v);
    v = 0.7500000000000000e-1;
    N = gen_oh( 3, N, x, y, z, w, a, b, v);
    N = N-1;
}

__device__ void LD0026(QUICKDouble* x, QUICKDouble* y, QUICKDouble* z, QUICKDouble* w, int N)
{
    /*
     ! W
     ! W    LEBEDEV    26-POINT ANGULAR GRID
     ! W
     ! vd
     ! vd   This subroutine is part of a set of subroutines that generate
     ! vd   Lebedev grids [1-6] for integration on a sphere. The original
     ! vd   C-code [1] was kindly provided by Dr. Dmitri N. Laikov and
     ! vd   translated into fortran by Dr. Christoph van Wuellen.
     ! vd   
     ! vd
     ! vd   Users of this code are asked to include reference [1] in their
     ! vd   publications, and in the user- and programmers-manuals
     ! vd   describing their codes.
     ! vd
     ! vd   This code was distributed through CCL (http://www.ccl.net/).
     ! vd
     ! vd   [1] V.I. Lebedev, and D.N. Laikov
     ! vd       "A quadrature formula for the sphere of the 131st
     ! vd        algebraic order of accuracy"
     ! vd       doklady Mathematics, Vol. 59, No. 3, 1999, pp. 477-481.
     ! vd
     ! vd   [2] V.I. Lebedev
     ! vd       "A quadrature formula for the sphere of 59th algebraic
     ! vd        order of accuracy"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 50, 1995, pp. 283-286.
     ! vd
     ! vd   [3] V.I. Lebedev, and A.L. Skorokhodov
     ! vd       "Quadrature formulas of orders 41, 47, and 53 for the sphere"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 45, 1992, pp. 587-592.
     ! vd
     ! vd   [4] V.I. Lebedev
     ! vd       "Spherical quadrature formulas exact to orders 25-29"
     ! vd       Siberian Mathematical Journal, Vol. 18, 1977, pp. 99-107.
     ! vd
     ! vd   [5] V.I. Lebedev
     ! vd       "Quadratures on a sphere"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 16,
     ! vd       1976, pp. 10-24.
     ! vd
     ! vd   [6] V.I. Lebedev
     ! vd       "Values of the nodes and weights of ninth to seventeenth
     ! vd        order Gauss-Markov quadrature formulae invariant under the
     ! vd        octahedron group with inversion"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 15,
     ! vd       1975, pp. 44-51.
     ! vd
     */
    N = 0;
    QUICKDouble a = 0;
    QUICKDouble b = 0;
    QUICKDouble v = 0.4761904761904762e-1;
    N = gen_oh( 1, N, x, y, z, w, a, b, v);
    v = 0.3809523809523810e-1;
    N = gen_oh( 2, N, x, y, z, w, a, b, v);
    v=0.3214285714285714e-1;
    N = gen_oh( 3, N, x, y, z, w, a, b, v);
}

__device__ void LD0038(QUICKDouble* x, QUICKDouble* y, QUICKDouble* z, QUICKDouble* w, int N)
{
    /*
     ! W
     ! W    LEBEDEV    38-POINT ANGULAR GRID
     ! W
     ! vd
     ! vd   This subroutine is part of a set of subroutines that generate
     ! vd   Lebedev grids [1-6] for integration on a sphere. The original
     ! vd   C-code [1] was kindly provided by Dr. Dmitri N. Laikov and
     ! vd   translated into fortran by Dr. Christoph van Wuellen.
     ! vd   
     ! vd
     ! vd   Users of this code are asked to include reference [1] in their
     ! vd   publications, and in the user- and programmers-manuals
     ! vd   describing their codes.
     ! vd
     ! vd   This code was distributed through CCL (http://www.ccl.net/).
     ! vd
     ! vd   [1] V.I. Lebedev, and D.N. Laikov
     ! vd       "A quadrature formula for the sphere of the 131st
     ! vd        algebraic order of accuracy"
     ! vd       doklady Mathematics, Vol. 59, No. 3, 1999, pp. 477-481.
     ! vd
     ! vd   [2] V.I. Lebedev
     ! vd       "A quadrature formula for the sphere of 59th algebraic
     ! vd        order of accuracy"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 50, 1995, pp. 283-286.
     ! vd
     ! vd   [3] V.I. Lebedev, and A.L. Skorokhodov
     ! vd       "Quadrature formulas of orders 41, 47, and 53 for the sphere"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 45, 1992, pp. 587-592.
     ! vd
     ! vd   [4] V.I. Lebedev
     ! vd       "Spherical quadrature formulas exact to orders 25-29"
     ! vd       Siberian Mathematical Journal, Vol. 18, 1977, pp. 99-107.
     ! vd
     ! vd   [5] V.I. Lebedev
     ! vd       "Quadratures on a sphere"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 16,
     ! vd       1976, pp. 10-24.
     ! vd
     ! vd   [6] V.I. Lebedev
     ! vd       "Values of the nodes and weights of ninth to seventeenth
     ! vd        order Gauss-Markov quadrature formulae invariant under the
     ! vd        octahedron group with inversion"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 15,
     ! vd       1975, pp. 44-51.
     ! vd
     */
    N = 0;
    QUICKDouble a = 0;
    QUICKDouble b = 0;
    QUICKDouble v = 0.9523809523809524e-2;
    N = gen_oh( 1, N, x, y, z, w, a, b, v);
    v = 0.3214285714285714e-1;
    N = gen_oh( 3, N, x, y, z, w, a, b, v);
    a =0.4597008433809831e+0;
    v =0.2857142857142857e-1;
    N = gen_oh( 5, N, x, y, z, w, a, b, v);
}

__device__ void LD0050(QUICKDouble* x, QUICKDouble* y, QUICKDouble* z, QUICKDouble* w, int N)
{
    /*
     ! W
     ! W    LEBEDEV    50-POINT ANGULAR GRID
     ! W
     ! vd
     ! vd   This subroutine is part of a set of subroutines that generate
     ! vd   Lebedev grids [1-6] for integration on a sphere. The original
     ! vd   C-code [1] was kindly provided by Dr. Dmitri N. Laikov and
     ! vd   translated into fortran by Dr. Christoph van Wuellen.
     ! vd   
     ! vd
     ! vd   Users of this code are asked to include reference [1] in their
     ! vd   publications, and in the user- and programmers-manuals
     ! vd   describing their codes.
     ! vd
     ! vd   This code was distributed through CCL (http://www.ccl.net/).
     ! vd
     ! vd   [1] V.I. Lebedev, and D.N. Laikov
     ! vd       "A quadrature formula for the sphere of the 131st
     ! vd        algebraic order of accuracy"
     ! vd       doklady Mathematics, Vol. 59, No. 3, 1999, pp. 477-481.
     ! vd
     ! vd   [2] V.I. Lebedev
     ! vd       "A quadrature formula for the sphere of 59th algebraic
     ! vd        order of accuracy"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 50, 1995, pp. 283-286.
     ! vd
     ! vd   [3] V.I. Lebedev, and A.L. Skorokhodov
     ! vd       "Quadrature formulas of orders 41, 47, and 53 for the sphere"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 45, 1992, pp. 587-592.
     ! vd
     ! vd   [4] V.I. Lebedev
     ! vd       "Spherical quadrature formulas exact to orders 25-29"
     ! vd       Siberian Mathematical Journal, Vol. 18, 1977, pp. 99-107.
     ! vd
     ! vd   [5] V.I. Lebedev
     ! vd       "Quadratures on a sphere"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 16,
     ! vd       1976, pp. 10-24.
     ! vd
     ! vd   [6] V.I. Lebedev
     ! vd       "Values of the nodes and weights of ninth to seventeenth
     ! vd        order Gauss-Markov quadrature formulae invariant under the
     ! vd        octahedron group with inversion"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 15,
     ! vd       1975, pp. 44-51.
     ! vd
     */
    N = 0;
    QUICKDouble a = 0;
    QUICKDouble b = 0;
    QUICKDouble v = 0.1269841269841270e-1;
    N = gen_oh( 1, N, x, y, z, w, a, b, v);
    v = 0.2257495590828924e-1;
    N = gen_oh( 2, N, x, y, z, w, a, b, v);
    v = 0.2109375000000000e-1;
    N = gen_oh( 3, N, x, y, z, w, a, b, v);
    a = 0.3015113445777636e+0;
    v = 0.2017333553791887e-1;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
}

__device__ void LD0074(QUICKDouble* x, QUICKDouble* y, QUICKDouble* z, QUICKDouble* w, int N)
{
    /*
     ! W
     ! W    LEBEDEV    74-POINT ANGULAR GRID
     ! W
     ! vd
     ! vd   This subroutine is part of a set of subroutines that generate
     ! vd   Lebedev grids [1-6] for integration on a sphere. The original
     ! vd   C-code [1] was kindly provided by Dr. Dmitri N. Laikov and
     ! vd   translated into fortran by Dr. Christoph van Wuellen.
     ! vd   
     ! vd
     ! vd   Users of this code are asked to include reference [1] in their
     ! vd   publications, and in the user- and programmers-manuals
     ! vd   describing their codes.
     ! vd
     ! vd   This code was distributed through CCL (http://www.ccl.net/).
     ! vd
     ! vd   [1] V.I. Lebedev, and D.N. Laikov
     ! vd       "A quadrature formula for the sphere of the 131st
     ! vd        algebraic order of accuracy"
     ! vd       doklady Mathematics, Vol. 59, No. 3, 1999, pp. 477-481.
     ! vd
     ! vd   [2] V.I. Lebedev
     ! vd       "A quadrature formula for the sphere of 59th algebraic
     ! vd        order of accuracy"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 50, 1995, pp. 283-286.
     ! vd
     ! vd   [3] V.I. Lebedev, and A.L. Skorokhodov
     ! vd       "Quadrature formulas of orders 41, 47, and 53 for the sphere"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 45, 1992, pp. 587-592.
     ! vd
     ! vd   [4] V.I. Lebedev
     ! vd       "Spherical quadrature formulas exact to orders 25-29"
     ! vd       Siberian Mathematical Journal, Vol. 18, 1977, pp. 99-107.
     ! vd
     ! vd   [5] V.I. Lebedev
     ! vd       "Quadratures on a sphere"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 16,
     ! vd       1976, pp. 10-24.
     ! vd
     ! vd   [6] V.I. Lebedev
     ! vd       "Values of the nodes and weights of ninth to seventeenth
     ! vd        order Gauss-Markov quadrature formulae invariant under the
     ! vd        octahedron group with inversion"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 15,
     ! vd       1975, pp. 44-51.
     ! vd
     */
    N = 0;
    QUICKDouble a = 0;
    QUICKDouble b = 0;
    QUICKDouble v = 0.5130671797338464e-3;
    N = gen_oh( 1, N, x, y, z, w, a, b, v);
    v = 0.1660406956574204e-1;
    N = gen_oh( 2, N, x, y, z, w, a, b, v);
    v = -0.2958603896103896e-1;
    N = gen_oh( 3, N, x, y, z, w, a, b, v);
    a = 0.4803844614152614;
    v = 0.2657620708215946e-1;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
    a = 0.3207726489807764;
    v = 0.1652217099371571e-1;
    N = gen_oh( 5, N, x, y, z, w, a, b, v);
}


__device__ void LD0086(QUICKDouble* x, QUICKDouble* y, QUICKDouble* z, QUICKDouble* w, int N)
{
    /*
     ! W
     ! W    LEBEDEV    86-POINT ANGULAR GRID
     ! W
     ! vd
     ! vd   This subroutine is part of a set of subroutines that generate
     ! vd   Lebedev grids [1-6] for integration on a sphere. The original
     ! vd   C-code [1] was kindly provided by Dr. Dmitri N. Laikov and
     ! vd   translated into fortran by Dr. Christoph van Wuellen.
     ! vd   
     ! vd
     ! vd   Users of this code are asked to include reference [1] in their
     ! vd   publications, and in the user- and programmers-manuals
     ! vd   describing their codes.
     ! vd
     ! vd   This code was distributed through CCL (http://www.ccl.net/).
     ! vd
     ! vd   [1] V.I. Lebedev, and D.N. Laikov
     ! vd       "A quadrature formula for the sphere of the 131st
     ! vd        algebraic order of accuracy"
     ! vd       doklady Mathematics, Vol. 59, No. 3, 1999, pp. 477-481.
     ! vd
     ! vd   [2] V.I. Lebedev
     ! vd       "A quadrature formula for the sphere of 59th algebraic
     ! vd        order of accuracy"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 50, 1995, pp. 283-286.
     ! vd
     ! vd   [3] V.I. Lebedev, and A.L. Skorokhodov
     ! vd       "Quadrature formulas of orders 41, 47, and 53 for the sphere"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 45, 1992, pp. 587-592.
     ! vd
     ! vd   [4] V.I. Lebedev
     ! vd       "Spherical quadrature formulas exact to orders 25-29"
     ! vd       Siberian Mathematical Journal, Vol. 18, 1977, pp. 99-107.
     ! vd
     ! vd   [5] V.I. Lebedev
     ! vd       "Quadratures on a sphere"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 16,
     ! vd       1976, pp. 10-24.
     ! vd
     ! vd   [6] V.I. Lebedev
     ! vd       "Values of the nodes and weights of ninth to seventeenth
     ! vd        order Gauss-Markov quadrature formulae invariant under the
     ! vd        octahedron group with inversion"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 15,
     ! vd       1975, pp. 44-51.
     ! vd
     */
    N = 0;
    QUICKDouble a = 0;
    QUICKDouble b = 0;
    QUICKDouble v = 0.1154401154401154e-1;
    N = gen_oh( 1, N, x, y, z, w, a, b, v);
    v = 0.1194390908585628e-1;
    N = gen_oh( 3, N, x, y, z, w, a, b, v);
    a = 0.3696028464541502;
    v = 0.1111055571060340e-1;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
    a = 0.6943540066026664;
    v = 0.1187650129453714e-1;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
    a = 0.3742430390903412;
    v = 0.1181230374690448e-1;
    N = gen_oh( 5, N, x, y, z, w, a, b, v);
}

__device__ void LD0110(QUICKDouble* x, QUICKDouble* y, QUICKDouble* z, QUICKDouble* w, int N)
{
    /*
     ! W
     ! W    LEBEDEV    110-POINT ANGULAR GRID
     ! W
     ! vd
     ! vd   This subroutine is part of a set of subroutines that generate
     ! vd   Lebedev grids [1-6] for integration on a sphere. The original
     ! vd   C-code [1] was kindly provided by Dr. Dmitri N. Laikov and
     ! vd   translated into fortran by Dr. Christoph van Wuellen.
     ! vd   
     ! vd
     ! vd   Users of this code are asked to include reference [1] in their
     ! vd   publications, and in the user- and programmers-manuals
     ! vd   describing their codes.
     ! vd
     ! vd   This code was distributed through CCL (http://www.ccl.net/).
     ! vd
     ! vd   [1] V.I. Lebedev, and D.N. Laikov
     ! vd       "A quadrature formula for the sphere of the 131st
     ! vd        algebraic order of accuracy"
     ! vd       doklady Mathematics, Vol. 59, No. 3, 1999, pp. 477-481.
     ! vd
     ! vd   [2] V.I. Lebedev
     ! vd       "A quadrature formula for the sphere of 59th algebraic
     ! vd        order of accuracy"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 50, 1995, pp. 283-286.
     ! vd
     ! vd   [3] V.I. Lebedev, and A.L. Skorokhodov
     ! vd       "Quadrature formulas of orders 41, 47, and 53 for the sphere"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 45, 1992, pp. 587-592.
     ! vd
     ! vd   [4] V.I. Lebedev
     ! vd       "Spherical quadrature formulas exact to orders 25-29"
     ! vd       Siberian Mathematical Journal, Vol. 18, 1977, pp. 99-107.
     ! vd
     ! vd   [5] V.I. Lebedev
     ! vd       "Quadratures on a sphere"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 16,
     ! vd       1976, pp. 10-24.
     ! vd
     ! vd   [6] V.I. Lebedev
     ! vd       "Values of the nodes and weights of ninth to seventeenth
     ! vd        order Gauss-Markov quadrature formulae invariant under the
     ! vd        octahedron group with inversion"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 15,
     ! vd       1975, pp. 44-51.
     ! vd
     */
    N = 0;
    QUICKDouble a = 0;
    QUICKDouble b = 0;
    QUICKDouble v = 0.3828270494937162e-2;
    N = gen_oh( 1, N, x, y, z, w, a, b, v);
    
    v = 0.9793737512487512e-2;
    N = gen_oh( 3, N, x, y, z, w, a, b, v);
    
    a = 0.1851156353447362;
    v = 0.8211737283191111e-2;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
    
    a = 0.6904210483822922;
    v = 0.9942814891178103e-2;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
    
    a = 0.3956894730559419;
    v = 0.9595471336070963e-2;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
    
    a = 0.4783690288121502;
    v = 0.9694996361663028e-2;
    N = gen_oh( 5, N, x, y, z, w, a, b, v);
}

__device__ void LD0146(QUICKDouble* x, QUICKDouble* y, QUICKDouble* z, QUICKDouble* w, int N)
{
    /*
     ! W
     ! W    LEBEDEV    146-POINT ANGULAR GRID
     ! W
     ! vd
     ! vd   This subroutine is part of a set of subroutines that generate
     ! vd   Lebedev grids [1-6] for integration on a sphere. The original
     ! vd   C-code [1] was kindly provided by Dr. Dmitri N. Laikov and
     ! vd   translated into fortran by Dr. Christoph van Wuellen.
     ! vd   
     ! vd
     ! vd   Users of this code are asked to include reference [1] in their
     ! vd   publications, and in the user- and programmers-manuals
     ! vd   describing their codes.
     ! vd
     ! vd   This code was distributed through CCL (http://www.ccl.net/).
     ! vd
     ! vd   [1] V.I. Lebedev, and D.N. Laikov
     ! vd       "A quadrature formula for the sphere of the 131st
     ! vd        algebraic order of accuracy"
     ! vd       doklady Mathematics, Vol. 59, No. 3, 1999, pp. 477-481.
     ! vd
     ! vd   [2] V.I. Lebedev
     ! vd       "A quadrature formula for the sphere of 59th algebraic
     ! vd        order of accuracy"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 50, 1995, pp. 283-286.
     ! vd
     ! vd   [3] V.I. Lebedev, and A.L. Skorokhodov
     ! vd       "Quadrature formulas of orders 41, 47, and 53 for the sphere"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 45, 1992, pp. 587-592.
     ! vd
     ! vd   [4] V.I. Lebedev
     ! vd       "Spherical quadrature formulas exact to orders 25-29"
     ! vd       Siberian Mathematical Journal, Vol. 18, 1977, pp. 99-107.
     ! vd
     ! vd   [5] V.I. Lebedev
     ! vd       "Quadratures on a sphere"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 16,
     ! vd       1976, pp. 10-24.
     ! vd
     ! vd   [6] V.I. Lebedev
     ! vd       "Values of the nodes and weights of ninth to seventeenth
     ! vd        order Gauss-Markov quadrature formulae invariant under the
     ! vd        octahedron group with inversion"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 15,
     ! vd       1975, pp. 44-51.
     ! vd
     */
    N = 0;
    QUICKDouble a = 0;
    QUICKDouble b = 0;
    QUICKDouble v=0.5996313688621381e-3;
    N = gen_oh( 1, N, x, y, z, w, a, b, v);
    
    v=0.7372999718620756e-2;
    N = gen_oh( 2, N, x, y, z, w, a, b, v);
    
    v=0.7210515360144488e-2;
    N = gen_oh( 3, N, x, y, z, w, a, b, v);
    
    a=0.6764410400114264e+0;
    v=0.7116355493117555e-2;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
    
    a=0.4174961227965453e+0;
    v=0.6753829486314477e-2;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
    
    a=0.1574676672039082e+0;
    v=0.7574394159054034e-2;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
    
    a=0.1403553811713183e+0;
    b=0.4493328323269557e+0;
    v=0.6991087353303262e-2;
    N = gen_oh( 6, N, x, y, z, w, a, b, v);
}

__device__ void LD0170(QUICKDouble* x, QUICKDouble* y, QUICKDouble* z, QUICKDouble* w, int N)
{
    /*
     ! W
     ! W    LEBEDEV    170-POINT ANGULAR GRID
     ! W
     ! vd
     ! vd   This subroutine is part of a set of subroutines that generate
     ! vd   Lebedev grids [1-6] for integration on a sphere. The original
     ! vd   C-code [1] was kindly provided by Dr. Dmitri N. Laikov and
     ! vd   translated into fortran by Dr. Christoph van Wuellen.
     ! vd   
     ! vd
     ! vd   Users of this code are asked to include reference [1] in their
     ! vd   publications, and in the user- and programmers-manuals
     ! vd   describing their codes.
     ! vd
     ! vd   This code was distributed through CCL (http://www.ccl.net/).
     ! vd
     ! vd   [1] V.I. Lebedev, and D.N. Laikov
     ! vd       "A quadrature formula for the sphere of the 131st
     ! vd        algebraic order of accuracy"
     ! vd       doklady Mathematics, Vol. 59, No. 3, 1999, pp. 477-481.
     ! vd
     ! vd   [2] V.I. Lebedev
     ! vd       "A quadrature formula for the sphere of 59th algebraic
     ! vd        order of accuracy"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 50, 1995, pp. 283-286.
     ! vd
     ! vd   [3] V.I. Lebedev, and A.L. Skorokhodov
     ! vd       "Quadrature formulas of orders 41, 47, and 53 for the sphere"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 45, 1992, pp. 587-592.
     ! vd
     ! vd   [4] V.I. Lebedev
     ! vd       "Spherical quadrature formulas exact to orders 25-29"
     ! vd       Siberian Mathematical Journal, Vol. 18, 1977, pp. 99-107.
     ! vd
     ! vd   [5] V.I. Lebedev
     ! vd       "Quadratures on a sphere"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 16,
     ! vd       1976, pp. 10-24.
     ! vd
     ! vd   [6] V.I. Lebedev
     ! vd       "Values of the nodes and weights of ninth to seventeenth
     ! vd        order Gauss-Markov quadrature formulae invariant under the
     ! vd        octahedron group with inversion"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 15,
     ! vd       1975, pp. 44-51.
     ! vd
     */
    N = 0;
    QUICKDouble a = 0;
    QUICKDouble b = 0;
    QUICKDouble v=0.5544842902037365e-2;
    N = gen_oh( 1, N, x, y, z, w, a, b, v);
    v=0.6071332770670752e-2;
    N = gen_oh( 2, N, x, y, z, w, a, b, v);
    v=0.6383674773515093e-2;
    N = gen_oh( 3, N, x, y, z, w, a, b, v);
    a=0.2551252621114134e+0;
    v=0.5183387587747790e-2;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
    a=0.6743601460362766e+0;
    v=0.6317929009813725e-2;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
    a=0.4318910696719410e+0;
    v=0.6201670006589077e-2;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
    a=0.2613931360335988e+0;
    v=0.5477143385137348e-2;
    N = gen_oh( 5, N, x, y, z, w, a, b, v);
    a=0.4990453161796037e+0;
    b=0.1446630744325115e+0;
    v=0.5968383987681156e-2;
    N = gen_oh( 6, N, x, y, z, w, a, b, v);
    
}

__device__ void LD0194(QUICKDouble* x, QUICKDouble* y, QUICKDouble* z, QUICKDouble* w, int N)
{
    /*
     ! W
     ! W    LEBEDEV    194-POINT ANGULAR GRID
     ! W
     ! vd
     ! vd   This subroutine is part of a set of subroutines that generate
     ! vd   Lebedev grids [1-6] for integration on a sphere. The original
     ! vd   C-code [1] was kindly provided by Dr. Dmitri N. Laikov and
     ! vd   translated into fortran by Dr. Christoph van Wuellen.
     ! vd   
     ! vd
     ! vd   Users of this code are asked to include reference [1] in their
     ! vd   publications, and in the user- and programmers-manuals
     ! vd   describing their codes.
     ! vd
     ! vd   This code was distributed through CCL (http://www.ccl.net/).
     ! vd
     ! vd   [1] V.I. Lebedev, and D.N. Laikov
     ! vd       "A quadrature formula for the sphere of the 131st
     ! vd        algebraic order of accuracy"
     ! vd       doklady Mathematics, Vol. 59, No. 3, 1999, pp. 477-481.
     ! vd
     ! vd   [2] V.I. Lebedev
     ! vd       "A quadrature formula for the sphere of 59th algebraic
     ! vd        order of accuracy"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 50, 1995, pp. 283-286.
     ! vd
     ! vd   [3] V.I. Lebedev, and A.L. Skorokhodov
     ! vd       "Quadrature formulas of orders 41, 47, and 53 for the sphere"
     ! vd       Russian Acad. Sci. dokl. Math., Vol. 45, 1992, pp. 587-592.
     ! vd
     ! vd   [4] V.I. Lebedev
     ! vd       "Spherical quadrature formulas exact to orders 25-29"
     ! vd       Siberian Mathematical Journal, Vol. 18, 1977, pp. 99-107.
     ! vd
     ! vd   [5] V.I. Lebedev
     ! vd       "Quadratures on a sphere"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 16,
     ! vd       1976, pp. 10-24.
     ! vd
     ! vd   [6] V.I. Lebedev
     ! vd       "Values of the nodes and weights of ninth to seventeenth
     ! vd        order Gauss-Markov quadrature formulae invariant under the
     ! vd        octahedron group with inversion"
     ! vd       Computational Mathematics and Mathematical Physics, Vol. 15,
     ! vd       1975, pp. 44-51.
     ! vd
     */
    N = 0;
    QUICKDouble a = 0;
    QUICKDouble b = 0;
    QUICKDouble v=0.1782340447244611e-2;
    N = gen_oh( 1, N, x, y, z, w, a, b, v);
    v=0.5716905949977102e-2;
    N = gen_oh( 2, N, x, y, z, w, a, b, v);
    v=0.5573383178848738e-2;
    N = gen_oh( 3, N, x, y, z, w, a, b, v);
    a=0.6712973442695226e+0;
    v=0.5608704082587997e-2;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
    a=0.2892465627575439e+0;
    v=0.5158237711805383e-2;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
    a=0.4446933178717437e+0;
    v=0.5518771467273614e-2;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
    a=0.1299335447650067e+0;
    v=0.4106777028169394e-2;
    N = gen_oh( 4, N, x, y, z, w, a, b, v);
    a=0.3457702197611283e+0;
    v=0.5051846064614808e-2;
    N = gen_oh( 5, N, x, y, z, w, a, b, v);
    a=0.1590417105383530e+0;
    b=0.8360360154824589e+0;
    v=0.5530248916233094e-2;
    N = gen_oh( 6, N, x, y, z, w, a, b, v);
}
