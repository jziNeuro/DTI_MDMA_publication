#!/bin/bash

# script to preprocess DTI data, perform automatic white matter budle segmentation and compute group difference regarding FA along white matter bundles
# script was used for the analysis in the article "White matter alterations in chronic MDMA use: Evidence from diffusion tensor imaging and neurofilament light chain blood levels"
# J. Zimmermann, 26.8.2022


# PREPROCESSING
#-------------------------------------------------------------------------------------------------------

# install QSIprep docker
# - see https://qsiprep.readthedocs.io/en/latest/index.html for further details about how to use QSIprep
pip install --user --upgrade qsiprep-container

# preprocess DTI data using QSIprep docker (data as NIfTI files and in BIDS format)
qsiprep-docker /mnt/share/DTI_data \
	/mnt/share/qsiprep_output participant \
	--output_resolution 2 \
	--fs-license-file /mnt/share/freesurfer_license/license.txt \
	-w /mnt/share/workdir \
	--ignore fieldmaps



# WHITE MATTER BUNDLE SEGMENTATION AND TRACTOMETRY
#-------------------------------------------------------------------------------------------------------

# install TractSeg (deep-learning based automatic white matter bundle segmentation)
# - see https://github.com/MIC-DKFZ/TractSeg for further details about TractSeg and how to use it
# - here, we apply the model that was pretrained on data from the human connectome project
pip install TractSeg

# install MRtrix3
# - see https://www.mrtrix.org/ for further details about MRtrix3
# - used to compute 
conda install -c mrtrix3 mrtrix3


# white matter bundle segmentation and tractometry
# - loop over all subjects
# - used to extract peaks of spherical harmonic function in each voxel

# get folder names of all participants
all_subjects=`ls /mnt/share/qsiprep_output/qsiprep/`$

# get output folder
tractseg_output_dir="tractseg_output"

for subj in $all_subjects
do
			echo ${subj}
			
			# get data path for subject
			data_path="/mnt/share/qsiprep_output/qsiprep/${subj}/dwi"
			
			# get output path for subject and create folder
			output_path="tractseg_output/${subj}"
			mkdir -p $output_path
			
			
			# compute MRtrix CSD peaks
			# - used later in TractSeg for segmentation
			dwi2response tournier ${data_path}/${subj}_space-T1w_desc-preproc_dwi.nii.gz \
				${output_path}/response.txt \
				-mask ${data_path}/${subj}_space-T1w_desc-brain_mask.nii.gz \
				-fslgrad ${data_path}/${subj}_space-T1w_desc-preproc_dwi.bvec ${data_path}/${subj}_space-T1w_desc-preproc_dwi.bval \
				-force
			
			dwi2fod csd ${data_path}/${subj}_space-T1w_desc-preproc_dwi.nii.gz \
				${output_path}/response.txt ${output_path}/WM_FODs.nii.gz \
				-mask ${data_path}/${subj}_space-T1w_desc-brain_mask.nii.gz \
				-fslgrad ${data_path}/${subj}_space-T1w_desc-preproc_dwi.bvec ${data_path}/${subj}_space-T1w_desc-preproc_dwi.bval \
				-force

			sh2peaks ${output_path}/WM_FODs.nii.gz \
				${output_path}/peaks.nii.gz \
				-force			
					
		
			# create bundle-specific tractograms based on CSD peaks using TractSeg
			# - create segmentation of bundles
			TractSeg -i ${output_path}/peaks.nii.gz -o ${output_path} --output_type tract_segmentation
			
			# - create segmentation of start and end regions of bundles
			TractSeg -i ${output_path}/peaks.nii.gz -o ${output_path} --output_type endings_segmentation
			
			# - create Tract Orientation Maps (TOMs) and use them to do bundle-specific tracking
			TractSeg -i ${output_path}/peaks.nii.gz -o ${output_path} --output_type TOM
			Tracking -i ${output_path}/peaks.nii.gz -o ${output_path}  --nr_fibers 5000 --tracking_format tck
			
			
			# compute FA map
			calc_FA -i ${data_path}/${subj}_space-T1w_desc-preproc_dwi.nii.gz \
				-o ${output_path}/${subj}_dwi_FAmap.nii.gz \
				--bvals ${data_path}/${subj}_space-T1w_desc-preproc_dwi.bval \
				--bvecs ${data_path}/${dwi_file_stem}.bvec \
				--brain_mask ${data_path}/${subj}_space-T1w_desc-brain_mask.nii.gz
			
			
			# perform tractometry
			# - see https://github.com/MIC-DKFZ/TractSeg/blob/master/resources/Tractometry_documentation.md for more details
			Tractometry -i ${output_path}/TOM_trackings/ \
				-o ${output_path}/${subj}_FA_tractometry.csv \
				-e ${output_path}/endings_segmentations/ \
				-s ${output_path}/${subj}_dwi_FAmap.nii.gz \
				--tracking_format tck

done




# COMPUTE GROUP DIFFERENCES AND CORRELATIONS
#-------------------------------------------------------------------------------------------------------

# - see https://github.com/MIC-DKFZ/TractSeg/blob/master/resources/Tractometry_documentation.md for more details
# - see https://github.com/MIC-DKFZ/TractSeg/blob/master/examples/subjects.txt for more information how to build design.txt file for group difference or correlation

# compute group difference or correlation along segments/tracts, performs multiple comparison correction and plot results per white matter bundle
plot_tractometry_results -i tractometry_design.txt \
	-o tractometry_result.png \
	--mc \
	--tracking_format tck \
	--save_csv







